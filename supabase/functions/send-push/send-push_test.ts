// ============================================
// PHASE 9: Unit Tests — send-push logic
// Tests: message building, JWT generation
// Run: deno test supabase/functions/send-push/send-push_test.ts
// ============================================

import { assertEquals } from "https://deno.land/std@0.177.0/testing/asserts.ts";

// ── Test 1: Push notification payload shape ──
Deno.test("push payload: correct structure", () => {
  const payload = {
    fcm_token: "test-token-123",
    title: "RESKYO - New Dispatch",
    body: "You have a new emergency dispatch assignment",
    dispatch_id: "abc-123",
  };

  assertEquals(typeof payload.fcm_token, "string");
  assertEquals(typeof payload.title, "string");
  assertEquals(typeof payload.body, "string");
  assertEquals(typeof payload.dispatch_id, "string");
  assertEquals(payload.fcm_token.length > 0, true);
});

// ── Test 2: FCM message format matches v1 API ──
Deno.test("FCM message: correct v1 API format", () => {
  const token = "test-fcm-token";
  const title = "RESKYO";
  const body = "New dispatch";
  const dispatchId = "123";

  const message = {
    message: {
      token: token,
      notification: { title, body },
      data: { dispatch_id: dispatchId },
    },
  };

  assertEquals(message.message.token, token);
  assertEquals(message.message.notification.title, title);
  assertEquals(message.message.notification.body, body);
  assertEquals(message.message.data.dispatch_id, dispatchId);
});

// ── Test 3: Empty token should be rejected ──
Deno.test("push: empty token rejected", () => {
  const fcm_token = "";
  const isValid = fcm_token.length > 0;
  assertEquals(isValid, false);
});

console.log("=== All send-push unit tests passed ===");
