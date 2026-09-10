//! Outbound mail. With `SMTP_URL` set mails really leave; without it every send is a
//! recorded dry-run. `POSTMARK_TOKEN` (preferred: synchronous errors) or `SMTP_URL`.
//! SMTP schemes: `smtps://user:pass@host:465` (implicit TLS),
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
    std::env::var("POSTMARK_TOKEN").is_ok() || std::env::var("SMTP_URL").is_ok()
}

/// Postmark's HTTP API. Unlike SMTP, which answers 250 and rejects later in the activity log,
/// it returns errors synchronously (e.g. 412 while the account is pending approval), so the
/// caller and `stellwerk mail-test` see them.
async fn send_postmark(token: &str, mail: &OutgoingMail<'_>) -> anyhow::Result<()> {
    use base64::Engine;
    let attachments: Vec<serde_json::Value> = mail
        .attachments
        .iter()
        .map(|(name, ct, bytes)| serde_json::json!({ "Name": name, "ContentType": ct, "Content": base64::engine::general_purpose::STANDARD.encode(bytes) }))
        .collect();
    let mut headers = vec![serde_json::json!({ "Name": "Message-ID", "Value": mail.message_id })];
    if let Some(r) = mail.in_reply_to {
        headers.push(serde_json::json!({ "Name": "In-Reply-To", "Value": r }));
        headers.push(serde_json::json!({ "Name": "References", "Value": r }));
    }
    let body = serde_json::json!({
        "From": mail.from,
        "To": mail.to,
        "Bcc": mail.bcc,
        "Subject": mail.subject,
        "TextBody": mail.body,
        "MessageStream": "outbound",
        "Headers": headers,
        "Attachments": attachments,
    });
    let client = reqwest::Client::builder().timeout(std::time::Duration::from_secs(30)).build()?;
    let r = client
        .post("https://api.postmarkapp.com/email")
        .header("X-Postmark-Server-Token", token)
        .header("Accept", "application/json")
        .json(&body)
        .send()
        .await?;
    let status = r.status();
    let v: serde_json::Value = r.json().await.unwrap_or_default();
    if !status.is_success() || v.get("ErrorCode").and_then(|c| c.as_i64()).unwrap_or(0) != 0 {
        anyhow::bail!(
            "Postmark {} (ErrorCode {}): {}",
            status.as_u16(),
            v.get("ErrorCode").and_then(|c| c.as_i64()).unwrap_or(0),
            v.get("Message").and_then(|m| m.as_str()).unwrap_or("no message")
        );
    }
    Ok(())
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
        let names: Vec<String> = mail.attachments.iter().map(|(n, _, b)| format!("{n} ({} B)", b.len())).collect();
        tracing::info!(from = %mail.from, to = %mail.to, subject = %mail.subject, attachments = %names.join(", "), "mail (dry-run): no POSTMARK_TOKEN/SMTP_URL, nothing sent");
        return Ok(SendResult::DryRun);
    }
    if let Ok(token) = std::env::var("POSTMARK_TOKEN") {
        send_postmark(&token, &mail).await?;
        return Ok(SendResult::Sent);
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
