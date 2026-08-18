insert into public.boards (slug, name, description, sort_order, is_public)
values ('continents', '대륙 게시판', '대륙 · 지형 · 도시 · 주요 장소', 35, true)
on conflict (slug) do update set name = excluded.name, description = excluded.description, is_public = true;

update public.boards
set description = '세계관 · 국가 · 역사 · 설정 자료'
where slug = 'world';
