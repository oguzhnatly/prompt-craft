import type { Env } from "./types";

// ─── Stripe Webhook Handler ─────────────────────────────────────────

export async function handleStripeWebhook(
  request: Request,
  env: Env,
  _ctx: ExecutionContext
): Promise<Response> {
  const signature = request.headers.get("Stripe-Signature");
  if (!signature) {
    return jsonResponse(400, { error: "Missing Stripe-Signature header." });
  }

  const rawBody = await request.text();

  // Verify signature using Web Crypto (no npm dependencies)
  const isValid = await verifyStripeSignature(
    rawBody,
    signature,
    env.STRIPE_WEBHOOK_SECRET
  );
  if (!isValid) {
    return jsonResponse(400, { error: "Invalid signature." });
  }

  let event: StripeEvent;
  try {
    event = JSON.parse(rawBody) as StripeEvent;
  } catch {
    return jsonResponse(400, { error: "Invalid JSON payload." });
  }

  try {
    switch (event.type) {
      case "checkout.session.completed":
        await handleCheckoutCompleted(event, env);
        break;
      case "customer.subscription.created":
        await handleSubscriptionCreated(event, env);
        break;
      case "customer.subscription.deleted":
        await handleSubscriptionDeleted(event, env);
        break;
      case "charge.refunded":
        await handleChargeRefunded(event, env);
        break;
      default:
        // Unhandled event type — acknowledge silently
        break;
    }
  } catch (err) {
    console.error(`Webhook handler error for ${event.type}:`, err);
    return jsonResponse(500, { error: "Internal webhook processing error." });
  }

  return jsonResponse(200, { received: true });
}

// ─── Stripe Signature Verification ──────────────────────────────────

async function verifyStripeSignature(
  payload: string,
  signatureHeader: string,
  secret: string
): Promise<boolean> {
  // Parse t= and v1= from the Stripe-Signature header
  const parts = signatureHeader.split(",");
  let timestamp = "";
  let sig = "";

  for (const part of parts) {
    const [key, value] = part.trim().split("=");
    if (key === "t") timestamp = value;
    if (key === "v1") sig = value;
  }

  if (!timestamp || !sig) return false;

  // Reject if timestamp is older than 5 minutes
  const timestampAge = Math.floor(Date.now() / 1000) - parseInt(timestamp, 10);
  if (timestampAge > 300) return false;

  // Compute HMAC-SHA256 of "{timestamp}.{payload}"
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const signed = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(`${timestamp}.${payload}`)
  );

  const expectedSig = Array.from(new Uint8Array(signed))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

  return timingSafeEqual(expectedSig, sig);
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let result = 0;
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return result === 0;
}

// ─── Event Handlers ─────────────────────────────────────────────────

async function handleCheckoutCompleted(
  event: StripeEvent,
  env: Env
): Promise<void> {
  const session = event.data.object as StripeCheckoutSession;

  // Only handle one-time payments (Pro) here; subscriptions handled separately
  if (session.mode === "subscription") return;

  const email = session.customer_email ?? session.customer_details?.email;
  const customerId = session.customer as string;

  if (!email) {
    console.error("checkout.session.completed: no email found");
    return;
  }

  // Create perpetual Keygen license
  const license = await createKeygenLicense(env, {
    email,
    tier: "pro",
    stripeCustomerId: customerId,
    policyId: env.KEYGEN_PRO_POLICY_ID,
  });

  if (license) {
    await sendLicenseEmail(env, email, license.key, "pro");
  }
}

async function handleSubscriptionCreated(
  event: StripeEvent,
  env: Env
): Promise<void> {
  const subscription = event.data.object as StripeSubscription;
  const customerId = subscription.customer as string;

  // Look up customer email from Stripe
  const email = await getStripeCustomerEmail(env, customerId);
  if (!email) {
    console.error("customer.subscription.created: no email found");
    return;
  }

  // Create subscription Keygen license
  const license = await createKeygenLicense(env, {
    email,
    tier: "cloud",
    stripeCustomerId: customerId,
    stripeSubscriptionId: subscription.id,
    policyId: env.KEYGEN_CLOUD_POLICY_ID,
  });

  if (license) {
    await sendLicenseEmail(env, email, license.key, "cloud");
  }
}

async function handleSubscriptionDeleted(
  event: StripeEvent,
  env: Env
): Promise<void> {
  const subscription = event.data.object as StripeSubscription;

  // Find license by subscription ID metadata
  const license = await findKeygenLicense(
    env,
    "stripeSubscriptionId",
    subscription.id
  );

  if (license) {
    await suspendKeygenLicense(env, license.id);
  }
}

async function handleChargeRefunded(
  event: StripeEvent,
  env: Env
): Promise<void> {
  const charge = event.data.object as StripeCharge;
  const customerId = charge.customer as string;

  if (!customerId) return;

  // Find license by customer ID metadata
  const license = await findKeygenLicense(
    env,
    "stripeCustomerId",
    customerId
  );

  if (license) {
    await revokeKeygenLicense(env, license.id);
  }
}

// ─── Keygen.sh API Helpers ──────────────────────────────────────────

interface CreateLicenseParams {
  email: string;
  tier: string;
  stripeCustomerId: string;
  stripeSubscriptionId?: string;
  policyId: string;
}

interface KeygenLicense {
  id: string;
  key: string;
}

async function createKeygenLicense(
  env: Env,
  params: CreateLicenseParams
): Promise<KeygenLicense | null> {
  const response = await fetch(
    `https://api.keygen.sh/v1/accounts/${env.KEYGEN_ACCOUNT_ID}/licenses`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/vnd.api+json",
        Accept: "application/vnd.api+json",
        Authorization: `Bearer ${env.KEYGEN_PRODUCT_TOKEN}`,
      },
      body: JSON.stringify({
        data: {
          type: "licenses",
          attributes: {
            metadata: {
              email: params.email,
              tier: params.tier,
              stripeCustomerId: params.stripeCustomerId,
              ...(params.stripeSubscriptionId && {
                stripeSubscriptionId: params.stripeSubscriptionId,
              }),
            },
          },
          relationships: {
            policy: {
              data: {
                type: "policies",
                id: params.policyId,
              },
            },
          },
        },
      }),
    }
  );

  if (!response.ok) {
    console.error(
      "Failed to create Keygen license:",
      response.status,
      await response.text()
    );
    return null;
  }

  const body = (await response.json()) as {
    data: { id: string; attributes: { key: string } };
  };

  return { id: body.data.id, key: body.data.attributes.key };
}

async function findKeygenLicense(
  env: Env,
  metadataKey: string,
  metadataValue: string
): Promise<{ id: string } | null> {
  const response = await fetch(
    `https://api.keygen.sh/v1/accounts/${env.KEYGEN_ACCOUNT_ID}/licenses?metadata[${metadataKey}]=${encodeURIComponent(metadataValue)}`,
    {
      method: "GET",
      headers: {
        Accept: "application/vnd.api+json",
        Authorization: `Bearer ${env.KEYGEN_PRODUCT_TOKEN}`,
      },
    }
  );

  if (!response.ok) return null;

  const body = (await response.json()) as {
    data: Array<{ id: string }>;
  };

  return body.data.length > 0 ? { id: body.data[0].id } : null;
}

async function suspendKeygenLicense(
  env: Env,
  licenseId: string
): Promise<void> {
  await fetch(
    `https://api.keygen.sh/v1/accounts/${env.KEYGEN_ACCOUNT_ID}/licenses/${licenseId}/actions/suspend`,
    {
      method: "POST",
      headers: {
        Accept: "application/vnd.api+json",
        Authorization: `Bearer ${env.KEYGEN_PRODUCT_TOKEN}`,
      },
    }
  );
}

async function revokeKeygenLicense(
  env: Env,
  licenseId: string
): Promise<void> {
  await fetch(
    `https://api.keygen.sh/v1/accounts/${env.KEYGEN_ACCOUNT_ID}/licenses/${licenseId}/actions/revoke`,
    {
      method: "POST",
      headers: {
        Accept: "application/vnd.api+json",
        Authorization: `Bearer ${env.KEYGEN_PRODUCT_TOKEN}`,
      },
    }
  );
}

// ─── Stripe API Helpers ─────────────────────────────────────────────

async function getStripeCustomerEmail(
  env: Env,
  customerId: string
): Promise<string | null> {
  const response = await fetch(
    `https://api.stripe.com/v1/customers/${customerId}`,
    {
      headers: {
        Authorization: `Bearer ${env.STRIPE_SECRET_KEY}`,
      },
    }
  );

  if (!response.ok) return null;

  const customer = (await response.json()) as { email?: string };
  return customer.email ?? null;
}

// ─── Resend Email ───────────────────────────────────────────────────

async function sendLicenseEmail(
  env: Env,
  email: string,
  licenseKey: string,
  tier: string
): Promise<void> {
  const tierLabel = tier === "cloud" ? "Cloud" : "Pro";
  const deepLink = `promptcraft://activate?key=${encodeURIComponent(licenseKey)}&email=${encodeURIComponent(email)}`;

  const htmlBody = `
    <h2>Your PromptCraft ${tierLabel} License</h2>
    <p>Thank you for your purchase! Here is your license key:</p>
    <pre style="background:#f4f4f4;padding:12px;border-radius:6px;font-size:16px;font-family:monospace;">${licenseKey}</pre>
    <p><a href="${deepLink}" style="display:inline-block;padding:12px 24px;background:#4F46E5;color:white;text-decoration:none;border-radius:8px;font-weight:600;">Activate in PromptCraft</a></p>
    <p style="color:#666;font-size:12px;">Or paste the license key manually in PromptCraft &rarr; Settings &rarr; License.</p>
  `;

  await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${env.RESEND_API_KEY}`,
    },
    body: JSON.stringify({
      from: "PromptCraft <noreply@promptcraft.app>",
      to: email,
      subject: `Your PromptCraft ${tierLabel} License Key`,
      html: htmlBody,
    }),
  });
}

// ─── Types ──────────────────────────────────────────────────────────

interface StripeEvent {
  type: string;
  data: {
    object: Record<string, unknown>;
  };
}

interface StripeCheckoutSession {
  mode: string;
  customer: unknown;
  customer_email?: string;
  customer_details?: { email?: string };
}

interface StripeSubscription {
  id: string;
  customer: unknown;
}

interface StripeCharge {
  customer: unknown;
}

// ─── Helpers ────────────────────────────────────────────────────────

function jsonResponse(
  status: number,
  body: Record<string, unknown>
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
