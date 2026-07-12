import { createClient } from "@supabase/supabase-js";

const execute = process.argv.includes("--execute");
const supabaseURL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const productionHost = "jevgtiamxlkucjqpbekn.supabase.co";
const protectedHandles = new Set(["tianfu-wu"]);
const protectedPostIDs = new Set(["fb291511-a07d-49e9-96ad-403f6336662c"]);
const e2eMarkers = ["e2e-knowyou-", "ky_e2e_"];
const fixedFixturePrefix = "eeeeeeee-";

if (!supabaseURL || new URL(supabaseURL).host !== productionHost) {
  fail(`NEXT_PUBLIC_SUPABASE_URL must target ${productionHost}`);
}
if (!serviceRoleKey) fail("SUPABASE_SERVICE_ROLE_KEY is required for the audit and cleanup");
if (execute && process.env.CONFIRM_NETWORKING_E2E_DELETE !== "1") {
  fail("CONFIRM_NETWORKING_E2E_DELETE=1 is required with --execute");
}

const admin = createClient(supabaseURL, serviceRoleKey, {
  auth: { autoRefreshToken: false, persistSession: false }
});

const users = await listAllUsers();
const { data: people, error: peopleError } = await admin.from("people").select("id,user_id,handle,display_name");
if (peopleError) fail(`people query failed: ${peopleError.message}`);

const e2eUserIDs = new Set(users.filter((user) => hasE2EMarker(user.email ?? "")).map((user) => user.id));
for (const person of people ?? []) {
  if (!protectedHandles.has(person.handle) && hasE2EMarker(person.handle)) e2eUserIDs.add(person.user_id);
}

const candidatePeople = (people ?? []).filter((person) => e2eUserIDs.has(person.user_id) && !protectedHandles.has(person.handle));
const candidatePersonIDs = candidatePeople.map((person) => person.id);
const candidateUsers = users.filter((user) => e2eUserIDs.has(user.id));

const [{ data: posts, error: postsError }, { data: comments, error: commentsError }] = await Promise.all([
  admin.from("posts").select("id,person_id,body"),
  admin.from("comments").select("id,person_id,post_id,body")
]);
if (postsError) fail(`posts query failed: ${postsError.message}`);
if (commentsError) fail(`comments query failed: ${commentsError.message}`);

const candidatePosts = (posts ?? []).filter((post) =>
  !protectedPostIDs.has(post.id) && (candidatePersonIDs.includes(post.person_id) || post.id.startsWith(fixedFixturePrefix))
);
const candidatePostIDs = new Set(candidatePosts.map((post) => post.id));
const candidateComments = (comments ?? []).filter((comment) =>
  !protectedPostIDs.has(comment.post_id) &&
  (candidatePersonIDs.includes(comment.person_id) || candidatePostIDs.has(comment.post_id) || comment.id.startsWith(fixedFixturePrefix))
);

const report = {
  mode: execute ? "EXECUTE" : "DRY RUN",
  users: candidateUsers.map(({ id, email }) => ({ id, email })),
  people: candidatePeople.map(({ id, user_id, handle, display_name }) => ({ id, userID: user_id, handle, displayName: display_name })),
  posts: candidatePosts.map(({ id, person_id, body }) => ({ id, personID: person_id, body })),
  comments: candidateComments.map(({ id, person_id, post_id, body }) => ({ id, personID: person_id, postID: post_id, body })),
  protected: { handles: [...protectedHandles], postIDs: [...protectedPostIDs] }
};
process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);

if (!execute) {
  process.stdout.write("DRY RUN only. Review every ID, then rerun with --execute and CONFIRM_NETWORKING_E2E_DELETE=1.\n");
  process.exit(0);
}

await deleteIDs("comments", candidateComments.map((item) => item.id));
await deleteIDs("posts", candidatePosts.map((item) => item.id));
for (const user of candidateUsers) {
  const { error } = await admin.auth.admin.deleteUser(user.id);
  if (error) fail(`auth user ${user.id} deletion failed: ${error.message}`);
}

process.stdout.write(`Deleted ${candidateUsers.length} E2E auth users, ${candidatePosts.length} posts, and ${candidateComments.length} comments.\n`);

function hasE2EMarker(value) {
  const normalized = value.toLowerCase();
  return e2eMarkers.some((marker) => normalized.includes(marker));
}

async function listAllUsers() {
  const result = [];
  for (let page = 1; ; page += 1) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 1000 });
    if (error) fail(`auth user query failed: ${error.message}`);
    result.push(...data.users);
    if (data.users.length < 1000) return result;
  }
}

async function deleteIDs(table, ids) {
  if (ids.length === 0) return;
  const { error } = await admin.from(table).delete().in("id", ids);
  if (error) fail(`${table} deletion failed: ${error.message}`);
}

function fail(message) {
  process.stderr.write(`Networking production cleanup failed: ${message}\n`);
  process.exit(1);
}
