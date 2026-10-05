-- Lista de salas abiertas usando la hora del servidor (evita problemas de reloj en el móvil)
create or replace function public.list_rooms()
returns table (code text, host_name text, map_id text, players int, max_players int)
language sql stable set search_path = public as $$
  select r.code, r.host_name, r.map_id, r.players, r.max_players
  from public.rooms r
  where r.status = 'open' and r.updated_at > now() - interval '60 seconds'
  order by r.created_at desc
  limit 30
$$;
revoke all on function public.list_rooms() from public, anon;
grant execute on function public.list_rooms() to authenticated;
