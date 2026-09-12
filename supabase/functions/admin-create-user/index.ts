import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type'
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  });

async function getInternalAuthEmail(loginValue: string) {
  const normalized = loginValue.trim().toLowerCase();
  const bytes = new TextEncoder().encode(normalized);
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  const hash = Array.from(new Uint8Array(digest)).map((byte) => byte.toString(16).padStart(2, '0')).join('');
  return `id-${hash}@open-door.local`;
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const authHeader = request.headers.get('Authorization');
    if (!authHeader) return json({ error: '관리자 인증이 필요합니다.' }, 401);

    const url = Deno.env.get('SUPABASE_URL')!;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const adminClient = createClient(url, serviceKey);
    const token = authHeader.replace('Bearer ', '');
    const { data: authData } = await adminClient.auth.getUser(token);
    if (!authData.user) return json({ error: '유효하지 않은 관리자 세션입니다.' }, 401);

    const { data: requester } = await adminClient
      .from('profiles')
      .select('role')
      .eq('id', authData.user.id)
      .single();
    if (requester?.role !== 'admin') return json({ error: '관리자만 계정을 생성할 수 있습니다.' }, 403);

    const body = await request.json();
    const loginId = String(body.loginId || '').trim().toLowerCase();
    const password = String(body.password || '');
    const nickname = String(body.nickname || loginId).trim();
    const character = body.character || {};

    if (!loginId || loginId.length > 120) return json({ error: '로그인 아이디를 입력해 주세요. (최대 120자)' }, 400);
    if (password.length < 8) return json({ error: '비밀번호는 8자 이상이어야 합니다.' }, 400);

    const internalEmail = await getInternalAuthEmail(loginId);
    const { data: created, error: createError } = await adminClient.auth.admin.createUser({
      email: internalEmail,
      password,
      email_confirm: true,
      user_metadata: { login_id: loginId, nickname }
    });
    if (createError) return json({ error: createError.message }, 400);

    const userId = created.user.id;
    const { error: profileError } = await adminClient.from('profiles').upsert({
      id: userId,
      nickname,
      role: 'user'
    });
    if (profileError) {
      await adminClient.auth.admin.deleteUser(userId);
      return json({ error: profileError.message }, 400);
    }

    if (String(character.name || '').trim()) {
      const { error: characterError } = await adminClient.from('characters').insert({
        owner_id: userId,
        name: String(character.name).trim(),
        class_name: String(character.roleName || '').trim(),
        content: String(character.roleTraits || '').trim(),
        status: 'published',
        role_name: String(character.roleName || '').trim(),
        role_traits: String(character.roleTraits || '').trim(),
        age: character.age ? Number(character.age) : null,
        height: character.height ? Number(character.height) : null,
        weight: character.weight ? Number(character.weight) : null,
        money: Number.isFinite(Number(character.money)) ? Math.min(Math.max(0, Math.floor(Number(character.money))), 2147483647) : 0
      });
      if (characterError) {
        await adminClient.auth.admin.deleteUser(userId);
        return json({ error: characterError.message }, 400);
      }
    }

    return json({ ok: true, userId });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : '계정 생성에 실패했습니다.' }, 500);
  }
});
