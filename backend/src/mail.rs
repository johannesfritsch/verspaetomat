//! Outbound mail. With `SMTP_URL` set mails really leave; without it every send is a
//! recorded dry-run. Schemes: `smtps://user:pass@host:465` (implicit TLS),
//! `smtp://user:pass@host:587` (STARTTLS), and `smtp://host:1025?starttls=no` for a
//! local sink without TLS (see `scripts/smtp-sink-check.sh`).

use lettre::message::{header::ContentType, Attachment, Mailbox, MultiPart, SinglePart};
use lettre::transport::smtp::authentication::Credentials;
use lettre::{AsyncSmtpTransport, AsyncTransport, Message, Tokio1Executor};

pub struct OutgoingMail<'a> {
    pub from: &'a str,
    pub to: &'a str,
    pub bcc: Option<&'a str>,
    pub subject: &'a str,
    pub body: &'a str,
    pub message_id: &'a str,
    pub in_reply_to: Option<&'a str>,
    pub attachments: Vec<(String, String, Vec<u8>)>, // (filename, content type, bytes)
}

pub enum SendResult {
    Sent,
    DryRun,
}

pub fn configured() -> bool {
    std::env::var("SMTP_URL").is_ok()
}

fn transport() -> anyhow::Result<AsyncSmtpTransport<Tokio1Executor>> {
    let url = std::env::var("SMTP_URL")?;
    let parsed = url::Url::parse(&url)?;
    let host = parsed.host_str().ok_or_else(|| anyhow::anyhow!("SMTP_URL host"))?.to_string();
    let port = parsed.port().unwrap_or(if parsed.scheme() == "smtp" { 587 } else { 465 });
    let user = parsed.username().to_string();
    let pass = parsed.password().unwrap_or("").to_string();
    let no_tls = parsed.query_pairs().any(|(k, v)| k == "starttls" && matches!(v.as_ref(), "no" | "false" | "0"));
    let builder = match (parsed.scheme(), no_tls) {
        ("smtps", _) => AsyncSmtpTransport::<Tokio1Executor>::relay(&host)?.port(port),
        ("smtp", false) => AsyncSmtpTransport::<Tokio1Executor>::starttls_relay(&host)?.port(port),
        ("smtp", true) => AsyncSmtpTransport::<Tokio1Executor>::builder_dangerous(&host).port(port),
        (other, _) => anyhow::bail!("SMTP_URL scheme {other}"),
    };
    let builder = if user.is_empty() { builder } else { builder.credentials(Credentials::new(user, pass)) };
    Ok(builder.build())
}

pub async fn send(mail: OutgoingMail<'_>) -> anyhow::Result<SendResult> {
    if !configured() {
        return Ok(SendResult::DryRun);
    }
    let from: Mailbox = mail.from.parse()?;
    let to: Mailbox = mail.to.parse()?;
    let mut b = Message::builder().from(from).to(to).subject(mail.subject).message_id(Some(mail.message_id.to_string()));
    if let Some(bcc) = mail.bcc {
        b = b.bcc(bcc.parse()?);
    }
    if let Some(r) = mail.in_reply_to {
        b = b.in_reply_to(r.to_string());
    }
    let mut mp = MultiPart::mixed().singlepart(SinglePart::builder().header(ContentType::TEXT_PLAIN).body(mail.body.to_string()));
    for (name, ct, bytes) in mail.attachments {
        let ct = ContentType::parse(&ct).unwrap_or(ContentType::TEXT_PLAIN);
        mp = mp.singlepart(Attachment::new(name).body(bytes, ct));
    }
    let msg = b.multipart(mp)?;
    transport()?.send(msg).await?;
    Ok(SendResult::Sent)
}
