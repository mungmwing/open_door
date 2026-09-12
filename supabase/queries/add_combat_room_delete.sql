-- 기존 실시간 전투 설치에 종료된 전투 기록 삭제 기능만 추가합니다.
-- 운영 DB에는 자동 적용하지 않습니다. Supabase SQL Editor에서 이 파일 전체를 실행하세요.
begin;

create or replace function public.combat_delete_room(p_room_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_status text;
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다.'; end if;
  if not public.is_admin() then raise exception '관리자만 전투 기록을 삭제할 수 있습니다.'; end if;

  select r.status into v_status
  from public.combat_rooms r
  where r.id = p_room_id and r.created_by = auth.uid()
  for update;

  if not found then raise exception '전투 기록을 삭제할 권한이 없습니다.'; end if;
  if v_status in ('waiting','active') then raise exception '진행 중인 전투는 종료한 뒤 삭제해 주세요.'; end if;

  delete from public.combat_rooms where id = p_room_id;
end; $$;

revoke all on function public.combat_delete_room(uuid) from public,anon;
grant execute on function public.combat_delete_room(uuid) to authenticated;
notify pgrst, 'reload schema';
commit;
