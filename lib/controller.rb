require "bundler/setup"
require "slack-notifier"
require "k8s-client"
require "concurrent"
require 'logger'
require 'yaml'
require 'mail'

require_relative "k8s_client"

Mail.defaults do
  delivery_method :smtp, address: ENV["EMAIL_SMTP_HOST"], port: ENV["EMAIL_SMTP_PORT"], user_name: ENV["EMAIL_SMTP_USERNAME"], password: ENV["EMAIL_SMTP_PASSWORD"]
end

class Controller
  TIMEOUT = 3600*24*365

  def initialize
    @presslabs_namespace = ENV.fetch("PRESSLABS_NAMESPACE", "mysql")

    @slack = Slack::Notifier.new ENV["SLACK_WEBHOOK"] do
      defaults channel: ENV["SLACK_CHANNEL"], username: ENV.fetch("SLACK_USERNAME", "Velero")
    end

    @k8s_client = Kubernetes::Client.new
    @logger = Logger.new(STDOUT)
  end

  def start
    $stdout.sync = true

    Thread.new do
      watch_backups
    end.join
  end

  private

  attr_reader :presslabs_namespace, :slack, :k8s_client, :logger

  def notify(event)
    backup_name = event.resource.metadata.name
    presslabs_namespace = @presslabs_namespace

    msg = case event.type
    when "ADDED"
      "Backup #{backup_name} started"

    when "MODIFIED"
      return unless event.resource.status.completed == true

      conditions = event.resource.status.conditions

      if conditions.detect { |c| c.type == "Failed" && c.status =~ /true/i }
        "Backup #{backup_name} FAILED"
      elsif conditions.detect { |c| c.type == "Complete" && c.status =~ /true/i }
        "Backup #{backup_name} completed successfully"
      else
        "Backup #{backup_name} completed but status is unknown"
      end

    else
      return
    end

    msg = "#{ENV.fetch("SUBJECT_PREFIX", "[MySQL]")} #{msg}"


    logger.info msg

    if ENV.fetch("ENABLE_SLACK_NOTIFICATIONS", "false") =~ /true/i
      at = if msg =~ /failed/i
             [:here]
           else
             []
           end

      attachment = {
        fallback: msg,
        text: msg,
        color: msg =~ /failed/i ? "danger" : "good"
      }

      begin
        slack.post at: at, attachments: [attachment]
      rescue => e
        logger.error "Something went wrong with the Slack notification: #{e.message}"
      end
    end

    if ENV.fetch("ENABLE_EMAIL_NOTIFICATIONS", "false") =~ /true/i
      begin
        mail = Mail.new do
          from    ENV["EMAIL_FROM_ADDRESS"]
          to      ENV["EMAIL_TO_ADDRESS"]
          subject msg
          body    "Run `kubectl -n #{presslabs_namespace} get MySQLBackup #{backup_name} -o yaml` for details."
        end

        mail.deliver!
      rescue => e
        logger.error "Something went wrong with the email notification: #{e.message}"
      end
    end
  end

  def watch_backups
    resource_version = k8s_client.api("mysql.presslabs.org/v1alpha1").resource("mysqlbackups", namespace: presslabs_namespace).meta_list.metadata.resourceVersion

    begin
      logger.info "Watching backups..."

      k8s_client.api("mysql.presslabs.org/v1alpha1").resource("mysqlbackups", namespace: presslabs_namespace).watch(timeout: TIMEOUT, resourceVersion: resource_version) do |event|
        resource_version = event.resource.metadata.resourceVersion
        notify event
      end

    rescue EOFError, Excon::Error::Socket
      logger.info "Reconnecting to API..."
      retry
    end
  end
end


