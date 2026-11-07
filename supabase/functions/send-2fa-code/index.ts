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
    const { email } = await req.json();

    if (!email) {
      return new Response(JSON.stringify({ error: 'Email is required' }), {
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

    // Check if 2FA is enabled for this user
    const twoFAEnabled = authUser.user_metadata?.two_fa_enabled === true;
    if (!twoFAEnabled) {
      return new Response(JSON.stringify({ error: '2FA_NOT_ENABLED' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Generate 6-digit code
    const code = Math.floor(100000 + Math.random() * 900000).toString();

    // Invalidate previous unused codes for this user
    await supabaseAdmin
      .from('user_2fa_codes')
      .update({ used: true })
      .eq('user_id', authUser.id)
      .eq('used', false);

    // Store new code
    const { error: insertError } = await supabaseAdmin.from('user_2fa_codes').insert({
      user_id: authUser.id,
      code,
      expires_at: new Date(Date.now() + 10 * 60 * 1000).toISOString(),
    });

    if (insertError) throw insertError;

    // Send email via Resend
    const resendApiKey = Deno.env.get('RESEND_API_KEY');
    if (resendApiKey) {
      await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${resendApiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          from: 'SintonIA <noreply@sintonia.app>',
          to: [email],
          subject: 'Seu código de verificação SintonIA',
          html: `
            <div style="font-family: sans-serif; max-width: 480px; margin: 0 auto; background: #0A0A0E; color: #fff; padding: 32px; border-radius: 16px;">
              <h2 style="background: linear-gradient(90deg, #C026D3, #00D2FF); -webkit-background-clip: text; -webkit-text-fill-color: transparent; font-size: 24px;">SintonIA</h2>
              <p style="color: #A1A1AA;">Seu código de verificação em duas etapas:</p>
              <div style="background: #18181B; border-radius: 12px; padding: 24px; text-align: center; margin: 24px 0; border: 1px solid #7C3AED44;">
                <span style="font-size: 40px; font-weight: bold; letter-spacing: 12px; color: #00D2FF;">${code}</span>
              </div>
              <p style="color: #A1A1AA; font-size: 13px;">Este código expira em 10 minutos. Não compartilhe com ninguém.</p>
            </div>
          `,
        }),
      });
    }

    return new Response(JSON.stringify({ success: true }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
