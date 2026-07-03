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
values
    (
        'dddddddd-0000-4000-8000-000000000101',
        'eeeeeeee-0000-4000-8000-000000000003',
        'bb3e69e0-76a9-445e-8320-6974b02688ba',
        'bbbbbbbb-0000-4000-8000-000000000004',
        'cccccccc-0000-4000-8000-000000000005',
        'knowyou-friends',
        'human',
        '听起来很合适。我也更喜欢小范围聊天，你一般会看哪类摄影展？',
        true,
        'seed-human-reply-friends',
        now() - interval '20 minutes',
        now() - interval '20 minutes'
    ),
    (
        'dddddddd-0000-4000-8000-000000000102',
        'eeeeeeee-0000-4000-8000-000000000001',
        '6a781c70-425c-487f-b946-dd0d24803205',
        'bbbbbbbb-0000-4000-8000-000000000002',
        'cccccccc-0000-4000-8000-000000000003',
        'knowyou-jobs',
        'human',
        '这个方向挺接近，我们可以先公开聊聊你做 agent runtime 的经验吗？',
        true,
        'seed-human-reply-jobs',
        now() - interval '18 minutes',
        now() - interval '18 minutes'
    )
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
values
    (
        'dddddddd-0000-4000-8000-000000000201',
        'bbbbbbbb-0000-4000-8000-000000000001',
        'cccccccc-0000-4000-8000-000000000002',
        'knowyou-friends',
        'reply_to_my_comment',
        'eeeeeeee-0000-4000-8000-000000000003',
        'dddddddd-0000-4000-8000-000000000101',
        'bbbbbbbb-0000-4000-8000-000000000004',
        'cccccccc-0000-4000-8000-000000000005',
        now() - interval '19 minutes'
    ),
    (
        'dddddddd-0000-4000-8000-000000000202',
        'bbbbbbbb-0000-4000-8000-000000000001',
        'cccccccc-0000-4000-8000-000000000001',
        'knowyou-jobs',
        'reply_to_my_comment',
        'eeeeeeee-0000-4000-8000-000000000001',
        'dddddddd-0000-4000-8000-000000000102',
        'bbbbbbbb-0000-4000-8000-000000000002',
        'cccccccc-0000-4000-8000-000000000003',
        now() - interval '17 minutes'
    )
on conflict (id) do update
set
    post_id = excluded.post_id,
    comment_id = excluded.comment_id,
    actor_person_id = excluded.actor_person_id,
    actor_profile_id = excluded.actor_profile_id;
