// Message text and number handling for the Send SMS hook. Pure functions,
// tested with Node (sms.test.ts).

/** The sign-in code message (S5). Short, plain, under 160 characters. */
export function otpMessage(code: string): string {
  return `Your S.A.G.I.P. code is ${code}. It expires in 5 minutes. Do not share it with anyone.`;
}

/**
 * Supabase stores numbers without the plus ("639170004821"). Semaphore
 * takes the local form ("09170004821"). Returns null for anything that is
 * not a Philippine mobile number.
 */
export function semaphoreNumber(phone: string): string | null {
  let digits = phone.replace(/\D/g, "");
  if (digits.startsWith("63")) digits = digits.slice(2);
  if (digits.startsWith("0")) digits = digits.slice(1);
  if (digits.length !== 10 || !digits.startsWith("9")) return null;
  return `0${digits}`;
}

/** "0917 ••• 4821": for logs, which never hold full numbers (RA 10173). */
export function maskNumber(phone: string): string {
  const digits = phone.replace(/\D/g, "");
  if (digits.length < 8) return "••••";
  const local = digits.startsWith("63") ? `0${digits.slice(2)}` : digits;
  return `${local.slice(0, 4)} ••• ${local.slice(-4)}`;
}

/** What Supabase Auth sends to the hook. */
export interface SendSmsPayload {
  user: { id: string; phone: string };
  sms: { otp: string };
}

export function parsePayload(body: string): SendSmsPayload | null {
  try {
    const json = JSON.parse(body);
    const phone = json?.user?.phone;
    const otp = json?.sms?.otp;
    const id = json?.user?.id;
    if (typeof phone !== "string" || typeof otp !== "string") return null;
    return { user: { id: String(id ?? ""), phone }, sms: { otp } };
  } catch {
    return null;
  }
}

/** The hook's error reply, in the shape Supabase Auth expects. */
export function hookError(httpCode: number, message: string): Response {
  return new Response(
    JSON.stringify({ error: { http_code: httpCode, message } }),
    { status: httpCode, headers: { "Content-Type": "application/json" } },
  );
}
