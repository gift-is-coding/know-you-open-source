begin;

do $integration$
declare
    selected_user_id uuid := gen_random_uuid();
    selected_session_id uuid := gen_random_uuid();
    test_device_id text := 'integration-' || gen_random_uuid()::text;
    test_handle text := 'integration-' || replace(gen_random_uuid()::text, '-', '');
    device_hash text := encode(extensions.digest(gen_random_uuid()::text, 'sha256'), 'hex');
    agent_hash text := encode(extensions.digest(gen_random_uuid()::text, 'sha256'), 'hex');
    replacement_agent_hash text := encode(extensions.digest(gen_random_uuid()::text, 'sha256'), 'hex');
    handoff_secret text := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
    handoff_hash text;
    replay_rejected boolean := false;
    bind_device_rejected boolean := false;
    create_handoff_rejected boolean := false;
    bind_handoff_rejected boolean := false;
    list_devices_rejected boolean := false;
    revoke_device_rejected boolean := false;
begin
    handoff_hash := encode(extensions.digest(handoff_secret, 'sha256'), 'hex');
    insert into auth.users (
        id, aud, role, email, email_confirmed_at,
        raw_app_meta_data, raw_user_meta_data, created_at, updated_at
    ) values (
        selected_user_id, 'authenticated', 'authenticated',
        'networking-integration-' || selected_user_id::text || '@example.invalid', now(),
        '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()
    );
    insert into auth.sessions (id, user_id, created_at, updated_at)
    values (selected_session_id, selected_user_id, now(), now());

    perform set_config(
        'request.jwt.claims',
        jsonb_build_object(
            'sub', selected_user_id::text,
            'session_id', selected_session_id::text,
            'role', 'authenticated'
        )::text,
        true
    );

    perform public.networking_begin_activation(
        'Networking Integration Test', test_handle, test_device_id, 'Integration Test Mac',
        device_hash, agent_hash, 'Integration test agent'
    );
    if not public.networking_current_session_has_active_device() then
        raise exception 'integration_activation_did_not_bind_session';
    end if;
    perform public.networking_create_web_handoff(
        test_device_id, device_hash, handoff_hash
    );

    perform public.networking_revoke_device(test_device_id);

    if exists (select 1 from auth.sessions where id = selected_session_id) then
        raise exception 'integration_auth_session_not_deleted';
    end if;
    if exists (
        select 1 from public.networking_device_sessions
        where auth_session_id = selected_session_id
    ) then
        raise exception 'integration_device_session_binding_not_deleted';
    end if;
    if public.networking_current_session_has_active_device() then
        raise exception 'integration_revoked_session_still_active';
    end if;
    if not exists (
        select 1 from public.agent_tokens
        where token_hash = agent_hash and revoked_at is not null
    ) then
        raise exception 'integration_agent_token_not_revoked';
    end if;

    begin
        perform public.networking_bind_current_device_session(test_device_id, device_hash);
    exception when others then
        if sqlerrm like '%networking_auth_required%' then bind_device_rejected := true; else raise; end if;
    end;
    begin
        perform public.networking_create_web_handoff(
            test_device_id, device_hash,
            encode(extensions.digest(gen_random_uuid()::text, 'sha256'), 'hex')
        );
    exception when others then
        if sqlerrm like '%networking_auth_required%' then create_handoff_rejected := true; else raise; end if;
    end;
    begin
        perform public.networking_bind_web_session(handoff_secret);
    exception when others then
        if sqlerrm like '%networking_auth_required%' then bind_handoff_rejected := true; else raise; end if;
    end;
    begin
        perform public.networking_list_devices();
    exception when others then
        if sqlerrm like '%networking_auth_required%' then list_devices_rejected := true; else raise; end if;
    end;
    begin
        perform public.networking_revoke_device('unrelated-device');
    exception when others then
        if sqlerrm like '%networking_auth_required%' then revoke_device_rejected := true; else raise; end if;
    end;
    if not bind_device_rejected or not create_handoff_rejected or not bind_handoff_rejected
       or not list_devices_rejected or not revoke_device_rejected then
        raise exception 'integration_revoked_session_binding_rpc_was_accepted';
    end if;

    begin
        perform public.networking_begin_activation(
            'Networking Integration Test', test_handle, test_device_id, 'Integration Test Mac',
            device_hash, replacement_agent_hash, 'Integration replay agent'
        );
    exception when others then
        if sqlerrm like '%networking_auth_required%' then
            replay_rejected := true;
        else
            raise;
        end if;
    end;
    if not replay_rejected then
        raise exception 'integration_revoked_jwt_replay_was_accepted';
    end if;
end
$integration$;

rollback;
select 'NETWORKING_DEVICE_REVOCATION_INTEGRATION_PASSED' as result;
