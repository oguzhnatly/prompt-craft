/**
 * Stripe webhook handler — drives the entire purchase automation
 * Flow: Stripe payment → webhook → create license → email via Resend → done
 * Zero external dependencies for licensing (in-house KV system)
 */

import { createLicense, renewCloud, suspendByCustomer } from './license';
import type { Env } from './types';

interface StripeEvent {
  id: string;
  type: string;
  data: { object: Record<string, unknown> };
}

// ── Stripe signature verification ────────────────────────────────────────────

async function verifyStripeSignature(
  body: string,
  signature: string,
  secret: string
): Promise<boolean> {
  const parts = signature.split(',').reduce<Record<string, string>>((acc, part) => {
    const [k, v] = part.split('=');
    acc[k] = v;
    return acc;
  }, {});

  const timestamp = parts['t'];
  const sigV1 = parts['v1'];
  if (!timestamp || !sigV1) return false;

  const payload = `${timestamp}.${body}`;
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  );
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(payload));
  const computed = Array.from(new Uint8Array(sig)).map(b => b.toString(16).padStart(2, '0')).join('');
  return computed === sigV1;
}

// ── Email via Resend ───────────────────────────────────────────────────────────

async function sendLicenseEmail(
  resendKey: string,
  to: string,
  licenseKey: string,
  tier: 'pro' | 'cloud',
  expiresAt?: string
): Promise<void> {
  if (!resendKey) return; // Skip if Resend not configured yet

  const tierLabel = tier === 'pro' ? 'Pro (Lifetime)' : 'Cloud';
  const body = tier === 'pro'
    ? `Your PromptCraft Pro license is ready.`
    : `Your PromptCraft Cloud subscription is active.${expiresAt ? ` Next renewal: ${new Date(expiresAt).toLocaleDateString()}.` : ''}`;

  await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${resendKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: 'PromptCraft <hello@promptcraft.app>',
      to: [to],
      subject: `Your PromptCraft ${tierLabel} License Key`,
      html: `
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width"></head>
<body style="margin:0;padding:0;background:#050507;color:#F7F8FC;font-family:'JetBrains Mono',monospace">
  <div style="max-width:560px;margin:0 auto;padding:48px 24px">
    <div style="margin-bottom:32px">
      <span style="font-size:20px;font-weight:700;letter-spacing:-0.03em">Prompt<span style="color:#00E5A0">Craft</span></span>
    </div>
    <h1 style="font-size:28px;font-weight:900;letter-spacing:-0.04em;margin-bottom:12px;color:#F7F8FC">${body}</h1>
    <p style="font-size:14px;color:#8892A4;line-height:1.7;margin-bottom:32px">Your license key is below. Enter it in PromptCraft → Preferences → License.</p>
    <div style="background:#0C0C10;border:1px solid rgba(0,229,160,0.2);border-radius:12px;padding:24px;margin-bottom:32px">
      <div style="font-size:11px;color:rgba(0,229,160,0.6);letter-spacing:0.1em;text-transform:uppercase;margin-bottom:8px">License Key</div>
      <div style="font-size:20px;font-weight:700;color:#00E5A0;letter-spacing:0.05em">${licenseKey}</div>
    </div>
    <div style="font-size:13px;color:#4B5563;line-height:1.7">
      <p>Need help? Reply to this email or visit <a href="https://promptcraft.app/docs" style="color:#00E5A0;text-decoration:none">promptcraft.app/docs</a></p>
    </div>
  </div>
</body>
</html>
      `.trim(),
    }),
  });
}

// ── Main handler ───────────────────────────────────────────────────────────────

export async function handleStripeWebhook(request: Request, env: Env): Promise<Response> {
  const body = await request.text();
  const signature = request.headers.get('stripe-signature') ?? '';

  // Verify signature
  const valid = await verifyStripeSignature(body, signature, env.STRIPE_WEBHOOK_SECRET ?? '');
  if (!valid) {
    return new Response('Invalid signature', { status: 401 });
  }

  let event: StripeEvent;
  try {
    event = JSON.parse(body) as StripeEvent;
  } catch {
    return new Response('Invalid JSON', { status: 400 });
  }

  const obj = event.data.object as Record<string, unknown>;

  try {
    switch (event.type) {

      case 'checkout.session.completed': {
        const session = obj as {
          customer_email?: string;
          customer?: string;
          subscription?: string;
          metadata?: { tier?: string };
          payment_status?: string;
          mode?: string;
        };

        const email = session.customer_email ?? '';
        const customerId = (session.customer ?? '') as string;
        const isSubscription = session.mode === 'subscription';
        const tier = isSubscription ? 'cloud' : 'pro';

        // For subscriptions, expiresAt is set on invoice.paid
        // For one-time (pro), no expiry
        const expiresAt = isSubscription
          ? new Date(Date.now() + 31 * 24 * 60 * 60 * 1000).toISOString()
          : undefined;

        const license = await createLicense(env.KV, {
          tier,
          email,
          customerId,
          subscriptionId: isSubscription ? (session.subscription as string) : undefined,
          expiresAt,
        });

        await sendLicenseEmail(
          env.RESEND_API_KEY ?? '',
          email,
          license.key,
          tier,
          expiresAt
        );

        console.log(`License created: ${license.key} [${tier}] → ${email}`);
        break;
      }

      case 'invoice.paid': {
        // Cloud subscription renewed — extend expiry by 31 days
        const invoice = obj as { customer?: string; lines?: { data?: Array<{ period?: { end?: number } }> } };
        const customerId = (invoice.customer ?? '') as string;
        const periodEnd = invoice.lines?.data?.[0]?.period?.end;
        if (customerId && periodEnd) {
          const expiresAt = new Date(periodEnd * 1000).toISOString();
          await renewCloud(env.KV, customerId, expiresAt);
          console.log(`Cloud license renewed for customer ${customerId} until ${expiresAt}`);
        }
        break;
      }

      case 'customer.subscription.deleted': {
        // Subscription cancelled or payment failed permanently
        const sub = obj as { customer?: string };
        if (sub.customer) {
          await suspendByCustomer(env.KV, sub.customer as string);
          console.log(`License suspended for customer ${sub.customer}`);
        }
        break;
      }

      case 'charge.refunded': {
        // Refund issued — suspend license
        const charge = obj as { customer?: string };
        if (charge.customer) {
          await suspendByCustomer(env.KV, charge.customer as string);
        }
        break;
      }
    }
  } catch (err) {
    console.error('Webhook handler error:', err);
    return new Response('Internal error', { status: 500 });
  }

  return new Response('OK', { status: 200 });
}
