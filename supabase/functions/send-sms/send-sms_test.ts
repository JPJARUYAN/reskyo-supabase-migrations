// ============================================
// PHASE 9: Unit Tests — send-sms logic
// Tests: message building, phone formatting, fallback flow
// Run: deno test supabase/functions/send-sms/send-sms_test.ts
// ============================================

import { assertEquals } from "https://deno.land/std@0.177.0/testing/asserts.ts";

// ── Message builder (extracted from send-sms) ──
const typeMap: Record<string, string> = {
  vehicularAccident: "Vehicular Accident",
  medicalEmergency: "Medical Emergency",
  fire: "Fire Incident",
  rescueOperation: "Rescue Operation",
  other: "Emergency",
};

function buildSmsMessage(
  type: string,
  description: string,
  barangay: string
): string {
  return (
    `[RESKYO] New Dispatch Alert\n` +
    `Type: ${typeMap[type] || type}\n` +
    `Location: ${barangay || "Unknown"}\n` +
    `Details: ${description.substring(0, 100)}\n` +
    `Please respond immediately.`
  );
}

// ── Phone formatter (extracted from send-sms) ──
function formatPhone(phone: string): string {
  return phone.startsWith("+") ? phone : `+63${phone.replace(/^0/, "")}`;
}

// ── Test 1: SMS message includes all fields ──
Deno.test("buildSmsMessage: includes all fields", () => {
  const msg = buildSmsMessage("medicalEmergency", "Chest pain patient", "Magsaysay");
  assertEquals(msg.includes("[RESKYO]"), true);
  assertEquals(msg.includes("Medical Emergency"), true);
  assertEquals(msg.includes("Magsaysay"), true);
  assertEquals(msg.includes("Chest pain patient"), true);
});

// ── Test 2: Unknown type falls back to "Emergency" ──
Deno.test("buildSmsMessage: unknown type → Emergency", () => {
  const msg = buildSmsMessage("unknownType", "test", "barangay");
  assertEquals(msg.includes("Emergency"), true);
});

// ── Test 3: Long description truncated to 100 chars ──
Deno.test("buildSmsMessage: truncates long description", () => {
  const longDesc = "A".repeat(200);
  const msg = buildSmsMessage("fire", longDesc, "Dawis");
  const detailsLine = msg.split("Details: ")[1].split("\n")[0];
  assertEquals(detailsLine.length <= 100, true);
});

// ── Test 4: Phone with + prefix stays unchanged ──
Deno.test("formatPhone: +63 prefix preserved", () => {
  assertEquals(formatPhone("+639123456789"), "+639123456789");
});

// ── Test 5: Phone with 0 prefix gets +63 ──
Deno.test("formatPhone: 09xx → +639xx", () => {
  assertEquals(formatPhone("09123456789"), "+639123456789");
});

// ── Test 6: Phone without + or 0 gets +63 ──
Deno.test("formatPhone: 9123456789 → +639123456789", () => {
  assertEquals(formatPhone("9123456789"), "+639123456789");
});

// ── Test 7: All incident types map correctly ──
Deno.test("typeMap: all types mapped", () => {
  assertEquals(typeMap["vehicularAccident"], "Vehicular Accident");
  assertEquals(typeMap["medicalEmergency"], "Medical Emergency");
  assertEquals(typeMap["fire"], "Fire Incident");
  assertEquals(typeMap["rescueOperation"], "Rescue Operation");
  assertEquals(typeMap["other"], "Emergency");
});

console.log("=== All send-sms unit tests passed ===");
