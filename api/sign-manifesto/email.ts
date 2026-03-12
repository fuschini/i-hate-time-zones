import { SESClient, SendEmailCommand } from "@aws-sdk/client-ses";

const ses = new SESClient({});
const FROM_EMAIL = process.env.FROM_EMAIL || "no-reply@ihatetimezones.com";
const SITE_URL = process.env.SITE_URL || "https://ihatetimezones.com";

export async function sendConfirmationEmail(
  toEmail: string,
  signatureNumber: number,
): Promise<void> {
  const refNumber = String(signatureNumber).padStart(5, "0");
  const subject = `You've Joined the Coalition — ICTS Ref. #${refNumber}`;

  const textBody = `INTERNATIONAL COALITION FOR TEMPORAL SANITY
Official Acknowledgment of Support

Reference: ICTS-${refNumber}

Dear Supporter,

Your support for the Manifesto for the Abolition of Time Zones has been formally recorded.

You are supporter #${signatureNumber.toLocaleString()}.

By joining, you have declared your opposition to the continued fragmentation of Earth's temporal experience into ${37} arbitrary zones. Your stance has been noted, cataloged, and preserved for posterity.

What happens next:
- Nothing immediate. The wheels of temporal reform turn slowly.
- You join a growing coalition of individuals who refuse to accept that a 30-minute flight can land yesterday.
- You may experience a heightened awareness of timezone-related absurdities. This is normal and, frankly, irreversible.

This communication was generated at a single, unambiguous moment in time — though we are legally required to note that the exact moment depends on which of the 37 zones you happen to inhabit. We find this deeply ironic.

Yours in temporal solidarity,

The International Coalition for Temporal Sanity
${SITE_URL}

---
You received this email because you joined the coalition at ${SITE_URL}.
If you did not, someone with access to your email shares your frustration with time zones.`;

  const htmlBody = `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body { font-family: Georgia, 'Times New Roman', serif; color: #1A1A18; line-height: 1.8; max-width: 600px; margin: 0 auto; padding: 2rem; }
    .header { text-align: center; border-bottom: 2px solid #1A1A18; padding-bottom: 1.5rem; margin-bottom: 2rem; }
    .org { font-family: 'Courier New', monospace; font-size: 10px; letter-spacing: 0.35em; text-transform: uppercase; color: #8A8A82; }
    .title { font-size: 18px; font-weight: bold; margin: 0.5rem 0; }
    .ref { font-family: 'Courier New', monospace; font-size: 11px; color: #8B2500; letter-spacing: 0.2em; }
    .body-text { font-size: 15px; color: #4A4A45; margin-bottom: 1rem; }
    .number { font-size: 28px; font-weight: bold; color: #8B2500; text-align: center; margin: 1.5rem 0; font-family: 'Courier New', monospace; }
    .list { margin: 1.5rem 0; padding-left: 1.5rem; }
    .list li { font-size: 14px; color: #4A4A45; margin-bottom: 0.75rem; }
    .sign-off { font-style: italic; margin-top: 2rem; color: #4A4A45; }
    .footer { border-top: 1px solid #D4D3CB; margin-top: 2rem; padding-top: 1rem; font-family: 'Courier New', monospace; font-size: 10px; color: #8A8A82; text-align: center; }
    a { color: #8B2500; }
  </style>
</head>
<body>
  <div class="header">
    <p class="org">International Coalition for Temporal Sanity</p>
    <p class="title">Official Acknowledgment of Support</p>
    <p class="ref">ICTS-${refNumber}</p>
  </div>

  <p class="body-text">Dear Supporter,</p>

  <p class="body-text">Your support for the Manifesto for the Abolition of Time Zones has been formally recorded.</p>

  <p class="number">Supporter #${signatureNumber.toLocaleString()}</p>

  <p class="body-text">By joining, you have declared your opposition to the continued fragmentation of Earth&rsquo;s temporal experience into 37 arbitrary zones. Your stance has been noted, cataloged, and preserved for posterity.</p>

  <p class="body-text"><strong>What happens next:</strong></p>
  <ul class="list">
    <li>Nothing immediate. The wheels of temporal reform turn slowly.</li>
    <li>You join a growing coalition of individuals who refuse to accept that a 30-minute flight can land <em>yesterday</em>.</li>
    <li>You may experience a heightened awareness of timezone-related absurdities. This is normal and, frankly, irreversible.</li>
  </ul>

  <p class="body-text sign-off">This communication was generated at a single, unambiguous moment in time &mdash; though we are legally required to note that the exact moment depends on which of the 37 zones you happen to inhabit. We find this deeply ironic.</p>

  <p class="body-text">Yours in temporal solidarity,</p>
  <p class="body-text"><strong>The International Coalition for Temporal Sanity</strong><br><a href="${SITE_URL}">${SITE_URL}</a></p>

  <div class="footer">
    <p>You received this email because you joined the coalition at <a href="${SITE_URL}">${SITE_URL}</a>.</p>
    <p>If you did not, someone with access to your email shares your frustration with time zones.</p>
  </div>
</body>
</html>`;

  const command = new SendEmailCommand({
    Source: FROM_EMAIL,
    Destination: { ToAddresses: [toEmail] },
    Message: {
      Subject: { Data: subject, Charset: "UTF-8" },
      Body: {
        Text: { Data: textBody, Charset: "UTF-8" },
        Html: { Data: htmlBody, Charset: "UTF-8" },
      },
    },
  });

  await ses.send(command);
}
