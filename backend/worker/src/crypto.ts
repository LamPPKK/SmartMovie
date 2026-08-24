import { RequestProblem } from "./validation";

const encoder = new TextEncoder();
const decoder = new TextDecoder();

export function randomToken(byteCount = 32): string {
  const bytes = new Uint8Array(byteCount);
  crypto.getRandomValues(bytes);
  return base64URL(bytes);
}

export async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(value));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

export async function encryptSecret(value: string, secret: string): Promise<string> {
  if (secret.length < 32) throw new RequestProblem(500, "missing_session_secret", "The session broker is not configured.");
  const key = await encryptionKey(secret, ["encrypt"]);
  const iv = new Uint8Array(12);
  crypto.getRandomValues(iv);
  const encrypted = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, encoder.encode(value));
  return `${base64URL(iv)}.${base64URL(new Uint8Array(encrypted))}`;
}

export async function decryptSecret(value: string, secret: string): Promise<string> {
  const [encodedIV, encodedCiphertext, extra] = value.split(".");
  if (!encodedIV || !encodedCiphertext || extra) throw new RequestProblem(500, "invalid_session_record", "The encrypted session record is invalid.");
  try {
    const key = await encryptionKey(secret, ["decrypt"]);
    const plaintext = await crypto.subtle.decrypt(
      { name: "AES-GCM", iv: decodeBase64URL(encodedIV) },
      key,
      decodeBase64URL(encodedCiphertext),
    );
    return decoder.decode(plaintext);
  } catch {
    throw new RequestProblem(401, "invalid_session", "The SmartMovie session is no longer valid.");
  }
}

export function secureEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return difference === 0;
}

async function encryptionKey(secret: string, usages: Array<"encrypt" | "decrypt">): Promise<CryptoKey> {
  const bytes = await crypto.subtle.digest("SHA-256", encoder.encode(secret));
  return crypto.subtle.importKey("raw", bytes, { name: "AES-GCM" }, false, usages);
}

function base64URL(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/u, "");
}

function decodeBase64URL(value: string): Uint8Array {
  const normalized = value.replaceAll("-", "+").replaceAll("_", "/");
  const padding = "=".repeat((4 - (normalized.length % 4)) % 4);
  const binary = atob(normalized + padding);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}
