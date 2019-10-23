# presslabs-backup-notification

This is a simple Kubernetes controller written in Ruby that sends email and/or Slack notifications when backups are performed by [Presslabs MySQL Operator](https://github.com/presslabs/mysql-operator).

## Installation

- Clone the repo
- Install with Helm

```bash
helm install ./helm \
  --name presslabs-backup-notification \
  --namespace mysql \
  --set presslabs_namespace=mysql \
  --set slack.enabled=true \
  --set slack.webhook=https://... \
  --set slack.channel=mysql \
  --set slack.username=MySQL \
  --set email.enabled=true \
  --set email.smtp.host=... \
  --set email.smtp.port=587 \
  --set email.smtp.username=... \
  --set email.smtp.password=... \
  --set email.from_address=... \
  --set email.to_address=... \
  --set subject_prefix="[MySQL]" \
  --set service_account=mysql-operator
```

That's it! You should now receive notifications when a backup is started and when it's completed.
