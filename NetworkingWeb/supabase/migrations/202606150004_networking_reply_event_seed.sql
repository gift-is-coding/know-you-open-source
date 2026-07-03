alter table public.public_interaction_events
    drop constraint if exists public_interaction_events_single_reference;

alter table public.public_interaction_events
    add constraint public_interaction_events_single_reference
    check (
        post_id is not null
        or comment_id is not null
    );

alter table public.comments
    drop constraint if exists comments_id_post_id_unique;
alter table public.comments
    add constraint comments_id_post_id_unique unique (id, post_id);

alter table public.public_interaction_events
    drop constraint if exists public_interaction_events_comment_matches_post;
alter table public.public_interaction_events
    add constraint public_interaction_events_comment_matches_post
    foreign key (comment_id, post_id)
    references public.comments(id, post_id)
    on delete cascade;

-- Demo reply seeds only apply when the demo posts/people/profiles from the
-- author's demo dataset exist. A fresh platform database skips them instead
-- of failing on foreign keys.
insert into public.comments(
    id,
    post_id,
    parent_comment_id,
    person_id,
    profile_id,
    platform_id,
    author_type,
    body,
    is_public,
    client_decision_id,
    created_at,
    updated_at
)
select
    seed.id,
    seed.post_id,
    seed.parent_comment_id,
    seed.person_id,
    seed.profile_id,
    seed.platform_id,
    seed.author_type::public.networking_author_type,
    seed.body,
    seed.is_public,
    seed.client_decision_id,
    seed.created_at,
    seed.updated_at
from (
    values
        (
            'dddddddd-0000-4000-8000-000000000101'::uuid,
            'eeeeeeee-0000-4000-8000-000000000003'::uuid,
            'bb3e69e0-76a9-445e-8320-6974b02688ba'::uuid,
            'bbbbbbbb-0000-4000-8000-000000000004'::uuid,
            'cccccccc-0000-4000-8000-000000000005'::uuid,
            'knowyou-friends',
            'human',
            '听起来很合适。我也更喜欢小范围聊天，你一般会看哪类摄影展？',
            true,
            'seed-human-reply-friends',
            now() - interval '20 minutes',
            now() - interval '20 minutes'
        ),
        (
            'dddddddd-0000-4000-8000-000000000102'::uuid,
            'eeeeeeee-0000-4000-8000-000000000001'::uuid,
            '6a781c70-425c-487f-b946-dd0d24803205'::uuid,
            'bbbbbbbb-0000-4000-8000-000000000002'::uuid,
            'cccccccc-0000-4000-8000-000000000003'::uuid,
            'knowyou-jobs',
            'human',
            '这个方向挺接近，我们可以先公开聊聊你做 agent runtime 的经验吗？',
            true,
            'seed-human-reply-jobs',
            now() - interval '18 minutes',
            now() - interval '18 minutes'
        )
) as seed(id, post_id, parent_comment_id, person_id, profile_id, platform_id, author_type, body, is_public, client_decision_id, created_at, updated_at)
where exists (select 1 from public.posts where posts.id = seed.post_id)
  and exists (select 1 from public.people where people.id = seed.person_id)
  and exists (select 1 from public.profiles where profiles.id = seed.profile_id)
  and exists (select 1 from public.comments where comments.id = seed.parent_comment_id)
on conflict (id) do update
set
    body = excluded.body,
    parent_comment_id = excluded.parent_comment_id,
    updated_at = excluded.updated_at;

insert into public.public_interaction_events(
    id,
    person_id,
    profile_id,
    platform_id,
    event_type,
    post_id,
    comment_id,
    actor_person_id,
    actor_profile_id,
    created_at
)
select
    seed.id,
    seed.person_id,
    seed.profile_id,
    seed.platform_id,
    seed.event_type,
    seed.post_id,
    seed.comment_id,
    seed.actor_person_id,
    seed.actor_profile_id,
    seed.created_at
from (
    values
        (
            'dddddddd-0000-4000-8000-000000000201'::uuid,
            'bbbbbbbb-0000-4000-8000-000000000001'::uuid,
            'cccccccc-0000-4000-8000-000000000002'::uuid,
            'knowyou-friends',
            'reply_to_my_comment',
            'eeeeeeee-0000-4000-8000-000000000003'::uuid,
            'dddddddd-0000-4000-8000-000000000101'::uuid,
            'bbbbbbbb-0000-4000-8000-000000000004'::uuid,
            'cccccccc-0000-4000-8000-000000000005'::uuid,
            now() - interval '19 minutes'
        ),
        (
            'dddddddd-0000-4000-8000-000000000202'::uuid,
            'bbbbbbbb-0000-4000-8000-000000000001'::uuid,
            'cccccccc-0000-4000-8000-000000000001'::uuid,
            'knowyou-jobs',
            'reply_to_my_comment',
            'eeeeeeee-0000-4000-8000-000000000001'::uuid,
            'dddddddd-0000-4000-8000-000000000102'::uuid,
            'bbbbbbbb-0000-4000-8000-000000000002'::uuid,
            'cccccccc-0000-4000-8000-000000000003'::uuid,
            now() - interval '17 minutes'
        )
) as seed(id, person_id, profile_id, platform_id, event_type, post_id, comment_id, actor_person_id, actor_profile_id, created_at)
where exists (select 1 from public.comments where comments.id = seed.comment_id)
on conflict (id) do update
set
    post_id = excluded.post_id,
    comment_id = excluded.comment_id,
    actor_person_id = excluded.actor_person_id,
    actor_profile_id = excluded.actor_profile_id;
