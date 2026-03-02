/**
 * PromptCraft In-House Licensing
 * Cloudflare KV backed. No third-party dependency.
 * Key format: PC-XXXX-XXXX-XXXX-XXXX
 */

export type LicenseTier = 'pro' | 'cloud';
export type LicenseStatus = 'active' | 'expired' | 'suspended' | 'invalid';

export interface License {
  key: string;
  tier: LicenseTier;
  status: LicenseStatus;
  email: string;
  customerId: string;
  subscriptionId?: string;
  machines: string[];
  maxMachines: number;
  createdAt: string;
  expiresAt?: string;
}

// ── Key generation ──────────────────────────────────────────────────

function seg(bytes: Uint8Array, offset: number): string {
  return Array.from(bytes.slice(offset, offset + 2))
    .map(b => b.toString(16).padStart(2, '0').toUpperCase())
    .join('');
}

export function generateLicenseKey(): string {
  const b = crypto.getRandomValues(new Uint8Array(8));
  return `PC-${seg(b,0)}-${seg(b,2)}-${seg(b,4)}-${seg(b,6)}`;
}

export async function hashLicenseKey(key: string): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(key));
  return Array.from(new Uint8Array(buf)).slice(0, 8).map(b => b.toString(16).padStart(2,'0')).join('');
}

// ── KV keys ────────────────────────────────────────────────────────

const K  = (key: string)   => `license:${key.toUpperCase()}`;
const KE = (email: string) => `email:${email.toLowerCase()}`;
const KC = (cid: string)   => `customer:${cid}`;

// ── CRUD ───────────────────────────────────────────────────────────

export async function createLicense(
  kv: KVNamespace,
  opts: {
    tier: LicenseTier;
    email: string;
    customerId: string;
    subscriptionId?: string;
    expiresAt?: string;
  }
): Promise<License> {
  const key = generateLicenseKey();
  const license: License = {
    key,
    tier: opts.tier,
    status: 'active',
    email: opts.email.toLowerCase(),
    customerId: opts.customerId,
    subscriptionId: opts.subscriptionId,
    machines: [],
    maxMachines: opts.tier === 'pro' ? 3 : 5,
    createdAt: new Date().toISOString(),
    expiresAt: opts.expiresAt,
  };
  await Promise.all([
    kv.put(K(key), JSON.stringify(license)),
    kv.put(KE(opts.email), key),
    kv.put(KC(opts.customerId), key),
  ]);
  return license;
}

export async function getLicenseByKey(kv: KVNamespace, key: string): Promise<License | null> {
  const raw = await kv.get(K(key));
  return raw ? (JSON.parse(raw) as License) : null;
}

export async function getLicenseByCustomer(kv: KVNamespace, cid: string): Promise<License | null> {
  const key = await kv.get(KC(cid));
  return key ? getLicenseByKey(kv, key) : null;
}

export async function setLicenseStatus(kv: KVNamespace, key: string, status: LicenseStatus): Promise<void> {
  const lic = await getLicenseByKey(kv, key);
  if (!lic) return;
  lic.status = status;
  await kv.put(K(key), JSON.stringify(lic));
}

export async function renewCloud(kv: KVNamespace, cid: string, expiresAt: string): Promise<void> {
  const lic = await getLicenseByCustomer(kv, cid);
  if (!lic) return;
  lic.status = 'active';
  lic.expiresAt = expiresAt;
  await kv.put(K(lic.key), JSON.stringify(lic));
}

export async function suspendByCustomer(kv: KVNamespace, cid: string): Promise<void> {
  const lic = await getLicenseByCustomer(kv, cid);
  if (lic) await setLicenseStatus(kv, lic.key, 'suspended');
}

// ── Validation (called from index.ts) ──────────────────────────────

export interface ValidationResult {
  valid: boolean;
  reason?: string;
  tier?: LicenseTier;
}

export async function validateLicense(
  key: string,
  env: { KV: KVNamespace }
): Promise<ValidationResult> {
  const lic = await getLicenseByKey(env.KV, key.trim().toUpperCase());

  if (!lic) return { valid: false, reason: 'License key not found.' };
  if (lic.status === 'suspended') return { valid: false, reason: 'License suspended. Contact support.' };
  if (lic.status === 'expired') return { valid: false, reason: 'License expired. Renew at promptcraft.app/pricing.' };

  // Auto-expire check for cloud
  if (lic.expiresAt && new Date(lic.expiresAt) < new Date()) {
    await setLicenseStatus(env.KV, key, 'expired');
    return { valid: false, reason: 'Cloud subscription expired. Renew at promptcraft.app/pricing.' };
  }

  return { valid: true, tier: lic.tier };
}
