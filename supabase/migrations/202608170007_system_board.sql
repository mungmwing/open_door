insert into public.boards (slug, name, description, sort_order, is_public)
values ('system', '시스템 게시판', '규칙 · 전투 · 판정 · 캠페인 시스템', 45, true)
on conflict (slug) do update set
  name = excluded.name,
  description = excluded.description,
  sort_order = excluded.sort_order,
  is_public = excluded.is_public;
