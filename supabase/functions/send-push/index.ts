import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

const FCM_SERVER_KEY = Deno.env.get("FCM_SERVER_KEY") ?? "";

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  try {
    const { fcm_token, title, body, dispatch_id } = await req.json();

    if (!fcm_token) {
      return new Response("No FCM token", { status: 400 });
    }

    const message = {
      to: fcm_token,
      notification: {
        title: title ?? "RESKYO Emergency Dispatch",
        body: body ?? "You have a new dispatch assignment",
      },
      data: {
        dispatch_id: dispatch_id ?? "",
      },
    };

    const response = await fetch("https://fcm.googleapis.com/fcm/send", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `key=${FCM_SERVER_KEY}`,
      },
      body: JSON.stringify(message),
    });

    const result = await response.json();

    return new Response(JSON.stringify(result), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
