import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': '*',
};

// Twilio JWT generation using Web Crypto API (Deno-compatible)
async function generateTwilioToken(
  accountSid: string,
  apiKeySid: string,
  apiKeySecret: string,
  identity: string,
  roomName: string,
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const exp = now + 3600; // 1 hour

  const header = { alg: 'HS256', typ: 'JWT', cty: 'twilio-fpa;v=1' };
  const grants = {
    identity,
    video: { room: roomName },
  };
  const payload = {
    jti: `${apiKeySid}-${now}`,
    iss: apiKeySid,
    sub: accountSid,
    exp,
    grants,
  };

  const encode = (obj: object) =>
    btoa(JSON.stringify(obj))
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=+$/, '');

  const headerB64 = encode(header);
  const payloadB64 = encode(payload);
  const signingInput = `${headerB64}.${payloadB64}`;

  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(apiKeySecret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );

  const signature = await crypto.subtle.sign(
    'HMAC',
    key,
    new TextEncoder().encode(signingInput),
  );

  const signatureB64 = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');

  return `${signingInput}.${signatureB64}`;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    // Verify auth
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } },
    );

    const { data: { user }, error: authError } = await supabaseClient.auth.getUser();
    if (authError || !user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const { roomName, callType } = await req.json();
    if (!roomName) {
      return new Response(JSON.stringify({ error: 'roomName is required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const accountSid = Deno.env.get('TWILIO_ACCOUNT_SID') ?? '';
    const apiKeySid = Deno.env.get('TWILIO_API_KEY_SID') ?? '';
    const apiKeySecret = Deno.env.get('TWILIO_API_KEY_SECRET') ?? '';

    if (!accountSid || !apiKeySid || !apiKeySecret) {
      return new Response(
        JSON.stringify({ error: 'Twilio credentials not configured' }),
        {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    const identity = user.id;
    const token = await generateTwilioToken(
      accountSid,
      apiKeySid,
      apiKeySecret,
      identity,
      roomName,
    );

    return new Response(
      JSON.stringify({ token, identity, roomName, callType: callType ?? 'video' }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      },
    );
  } catch (error) {
    console.error('Error generating Twilio token:', error);
    return new Response(JSON.stringify({ error: 'Internal server error' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
