import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const { email, code } = await req.json();

    if (!email || !code) {
      return new Response(JSON.stringify({ error: 'Email and code are required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    );

    // Find user by email
    const { data: users, error: userError } = await supabaseAdmin.auth.admin.listUsers();
    if (userError) throw userError;

    const authUser = users.users.find((u) => u.email === email);
    if (!authUser) {
      return new Response(JSON.stringify({ error: 'USER_NOT_FOUND' }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Find valid code
    const { data: codeRecord, error: codeError } = await supabaseAdmin
      .from('user_2fa_codes')
      .select('*')
      .eq('user_id', authUser.id)
      .eq('code', code)
      .eq('used', false)
      .gte('expires_at', new Date().toISOString())
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (codeError) throw codeError;

    if (!codeRecord) {
      return new Response(JSON.stringify({ error: 'INVALID_OR_EXPIRED_CODE' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Mark code as used
    await supabaseAdmin
      .from('user_2fa_codes')
      .update({ used: true })
      .eq('id', codeRecord.id);

    return new Response(JSON.stringify({ success: true, verified: true }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
