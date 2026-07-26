// ============================================
// PHASE 3, Step 2: send-sms Edge Function
// Invoked by Database Webhook when a new dispatch is created.
// Calls Android SMS Gateway REST API to send SMS alerts.
// Deploy: supabase functions deploy send-sms
// Set secrets: supabase secrets set SMS_GATEWAY_URL=... SMS_GATEWAY_API_KEY=...
// ============================================

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Get request body (from database webhook)
    const body = await req.json();
    const { record: dispatch, type } = body;

    // Only process INSERT events
    if (type !== "INSERT" || !dispatch) {
      return new Response(
        JSON.stringify({ message: "Ignored: not a new dispatch" }),
        { status: 200, headers: corsHeaders }
      );
    }

    // Supabase client with service role for full access
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const smsGatewayUrl = Deno.env.get("SMS_GATEWAY_URL")!;
    const smsGatewayApiKey = Deno.env.get("SMS_GATEWAY_API_KEY") || "";

    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Get responder's phone number
    const { data: responder, error: responderError } = await supabase
      .from("users")
      .select("contact_number, full_name")
      .eq("uid", dispatch.responder_id)
      .single();

    if (responderError || !responder) {
      console.error("Failed to fetch responder:", responderError);
      return new Response(
        JSON.stringify({ error: "Responder not found" }),
        { status: 404, headers: corsHeaders }
      );
    }

    // Get incident details
    const { data: incident, error: incidentError } = await supabase
      .from("incidents")
      .select("type, description, barangay, latitude, longitude")
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
    const incidentTypeMap: Record<string, string> = {
      vehicularAccident: "Vehicular Accident",
      medicalEmergency: "Medical Emergency",
      fire: "Fire Incident",
      rescueOperation: "Rescue Operation",
      other: "Emergency",
    };

    const smsMessage =
      `[RESKYO] New Dispatch Alert\n` +
      `Type: ${incidentTypeMap[incident.type] || incident.type}\n` +
      `Location: ${incident.barangay || "Unknown"}\n` +
      `Details: ${incident.description.substring(0, 100)}\n` +
      `Please respond immediately.`;

    // Send SMS via Android SMS Gateway
    let smsStatus = "sent";
    let smsError = "";

    try {
      const smsResponse = await fetch(smsGatewayUrl, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${smsGatewayApiKey}`,
        },
        body: JSON.stringify({
          to: responder.contact_number,
          message: smsMessage,
        }),
      });

      if (!smsResponse.ok) {
        smsStatus = "failed";
        smsError = `Gateway returned ${smsResponse.status}: ${await smsResponse.text()}`;
        console.error("SMS Gateway error:", smsError);
      }
    } catch (fetchError) {
      smsStatus = "failed";
      smsError = `Gateway unreachable: ${fetchError.message}`;
      console.error("SMS Gateway fetch failed:", smsError);
    }

    // Log to sms_logs
    const { error: logError } = await supabase.from("sms_logs").insert({
      dispatch_id: dispatch.id,
      phone_number: responder.contact_number,
      message: smsMessage,
      status: smsStatus,
      sent_at: new Date().toISOString(),
      error_message: smsError || null,
    });

    if (logError) {
      console.error("Failed to log SMS:", logError);
    }

    return new Response(
      JSON.stringify({
        message: "SMS processed",
        status: smsStatus,
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
