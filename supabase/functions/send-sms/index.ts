// ============================================
// PHASE 8: send-sms Edge Function
// Invoked by Database Trigger when a new dispatch is created.
// Uses capcom6/android-sms-gateway in Cloud mode.
//
// Deploy: supabase functions deploy send-sms
// Set secrets:
//   supabase secrets set SMS_GATEWAY_USERNAME=<from-app>
//   supabase secrets set SMS_GATEWAY_PASSWORD=<from-app>
//
// Cloud API: POST https://api.sms-gate.app/3rdparty/v1/message
// Auth: HTTP Basic Auth (username:password)
// Body: { "textMessage": { "text": "..." }, "phoneNumbers": ["+639..."] }
// ============================================

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const SMS_CLOUD_URL = "https://api.sms-gate.app/3rdparty/v1/message";

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body = await req.json();
    const { record: dispatch, type } = body;

    if (type !== "INSERT" || !dispatch) {
      return new Response(
        JSON.stringify({ message: "Ignored: not a new dispatch" }),
        { status: 200, headers: corsHeaders }
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const smsUsername = Deno.env.get("SMS_GATEWAY_USERNAME") || "";
    const smsPassword = Deno.env.get("SMS_GATEWAY_PASSWORD") || "";

    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Fetch responder (phone + FCM token for fallback)
    const { data: responder, error: responderError } = await supabase
      .from("users")
      .select("contact_number, full_name, fcm_token")
      .eq("uid", dispatch.responder_id)
      .single();

    if (responderError || !responder) {
      console.error("Failed to fetch responder:", responderError);
      return new Response(
        JSON.stringify({ error: "Responder not found" }),
        { status: 404, headers: corsHeaders }
      );
    }

    // Fetch incident details
    const { data: incident, error: incidentError } = await supabase
      .from("incidents")
      .select("type, description, barangay")
      .eq("id", dispatch.incident_id)
      .single();

    if (incidentError || !incident) {
      console.error("Failed to fetch incident:", incidentError);
      return new Response(
        JSON.stringify({ error: "Incident not found" }),
        { status: 404, headers: corsHeaders }
      );
    }

    // Build SMS message
    const typeMap: Record<string, string> = {
      vehicularAccident: "Vehicular Accident",
      medicalEmergency: "Medical Emergency",
      fire: "Fire Incident",
      rescueOperation: "Rescue Operation",
      other: "Emergency",
    };

    const smsMessage =
      `[RESKYO] New Dispatch Alert\n` +
      `Type: ${typeMap[incident.type] || incident.type}\n` +
      `Location: ${incident.barangay || "Unknown"}\n` +
      `Details: ${incident.description.substring(0, 100)}\n` +
      `Please respond immediately.`;

    // ── Step 1: Send SMS via Cloud Gateway ──
    let smsStatus = "sent";
    let smsError = "";

    if (!smsUsername || !smsPassword) {
      smsStatus = "skipped";
      smsError = "SMS_GATEWAY_USERNAME or SMS_GATEWAY_PASSWORD not configured";
      console.warn("SMS skipped:", smsError);
    } else {
      try {
        const credentials = btoa(`${smsUsername}:${smsPassword}`);
        const phone = responder.contact_number.startsWith("+")
          ? responder.contact_number
          : `+63${responder.contact_number.replace(/^0/, "")}`;

        const smsResponse = await fetch(SMS_CLOUD_URL, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Basic ${credentials}`,
          },
          body: JSON.stringify({
            textMessage: { text: smsMessage },
            phoneNumbers: [phone],
          }),
        });

        if (!smsResponse.ok) {
          smsStatus = "failed";
          smsError = `Gateway ${smsResponse.status}: ${await smsResponse.text()}`;
          console.error("SMS failed:", smsError);
        }
      } catch (fetchError) {
        smsStatus = "failed";
        smsError = `Gateway unreachable: ${fetchError.message}`;
        console.error("SMS fetch failed:", smsError);
      }
    }

    // ── Step 2: Log SMS ──
    await supabase.from("sms_logs").insert({
      dispatch_id: dispatch.id,
      phone_number: responder.contact_number,
      message: smsMessage,
      status: smsStatus,
      sent_at: new Date().toISOString(),
      error_message: smsError || null,
    });

    // ── Step 3: Fallback — if SMS failed, fire FCM push ──
    let pushStatus = "not_needed";

    if (smsStatus === "failed" || smsStatus === "skipped") {
      if (responder.fcm_token) {
        try {
          const pushResponse = await fetch(
            `${supabaseUrl}/functions/v1/send-push`,
            {
              method: "POST",
              headers: {
                "Content-Type": "application/json",
                Authorization: `Bearer ${supabaseServiceKey}`,
              },
              body: JSON.stringify({
                fcm_token: responder.fcm_token,
                title: "RESKYO - New Dispatch",
                body: `New ${typeMap[incident.type] || "emergency"} in ${incident.barangay || "Unknown"}. Please respond.`,
                dispatch_id: dispatch.id,
              }),
            }
          );

          pushStatus = pushResponse.ok ? "sent" : "failed";
          console.log(`FCM fallback: ${pushStatus}`);
        } catch (pushError) {
          pushStatus = "failed";
          console.error("FCM fallback failed:", pushError);
        }
      } else {
        pushStatus = "no_token";
        console.warn("No FCM token for responder:", dispatch.responder_id);
      }
    }

    return new Response(
      JSON.stringify({
        message: "Dispatch notification processed",
        sms: { status: smsStatus, error: smsError || null },
        push: { status: pushStatus },
        responder: responder.full_name,
        phone: responder.contact_number,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (error) {
    console.error("send-sms error:", error);
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});
