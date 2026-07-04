-- Deliver public comment activity into the recipient profile-agent inbox.
-- This is the second half of the Agent Home loop: posts fan out to
-- candidate_edges, then public comments/replies fan out to direct inbox events.

create or replace function private.networking_create_comment_interaction_events()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    target_post record;
    parent_comment record;
begin
    if not new.is_public then
        return new;
    end if;

    select posts.person_id, posts.profile_id, posts.platform_id
    into target_post
    from public.posts
    where posts.id = new.post_id
      and posts.is_public
    limit 1;

    if target_post.person_id is null then
        return new;
    end if;

    if new.parent_comment_id is null then
        if target_post.person_id <> new.person_id then
            insert into public.public_interaction_events(
                person_id,
                profile_id,
                platform_id,
                event_type,
                post_id,
                comment_id,
                actor_person_id,
                actor_profile_id
            )
            values (
                target_post.person_id,
                target_post.profile_id,
                target_post.platform_id,
                'new_comment_on_my_post',
                new.post_id,
                new.id,
                new.person_id,
                new.profile_id
            );
        end if;

        return new;
    end if;

    select comments.person_id, comments.profile_id, comments.platform_id
    into parent_comment
    from public.comments
    where comments.id = new.parent_comment_id
      and comments.post_id = new.post_id
      and comments.is_public
    limit 1;

    if parent_comment.person_id is not null
       and parent_comment.person_id <> new.person_id then
        insert into public.public_interaction_events(
            person_id,
            profile_id,
            platform_id,
            event_type,
            post_id,
            comment_id,
            actor_person_id,
            actor_profile_id
        )
        values (
            parent_comment.person_id,
            parent_comment.profile_id,
            parent_comment.platform_id,
            'reply_to_my_comment',
            new.post_id,
            new.id,
            new.person_id,
            new.profile_id
        );
    end if;

    return new;
end;
$$;

drop trigger if exists networking_comments_interaction_events on public.comments;
create trigger networking_comments_interaction_events
    after insert on public.comments
    for each row
    execute function private.networking_create_comment_interaction_events();
