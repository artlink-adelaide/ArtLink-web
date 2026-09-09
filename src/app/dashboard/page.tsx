import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export const metadata = { title: "Dashboard — ArtLink" };

const EMPTY_SECTIONS = [
  { title: "作品", hint: "你还没有发布任何作品。作品集功能将在后续阶段开放。" },
  { title: "活动", hint: "你还没有主办任何活动。活动功能将在后续阶段开放。" },
  { title: "报名", hint: "你还没有报名任何活动。报名功能将在后续阶段开放。" },
] as const;

export default async function DashboardPage() {
  const supabase = await createSupabaseServerClient();

  // HARD RULE: authorization via getUser() (server verified). The
  // middleware already gates this route; this is defense in depth.
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const { data: profile } = await supabase
    .from("profiles")
    .select("handle, display_name, account_kind, category_id")
    .eq("id", user.id)
    .maybeSingle();

  if (profile == null || profile.category_id == null) {
    redirect("/onboarding");
  }

  return (
    <main className="mx-auto flex w-full max-w-5xl flex-col gap-6 px-4 py-10">
      <header>
        <h1 className="text-2xl font-semibold">
          你好，{profile.display_name}
          <span className="ml-2 font-mono text-sm text-muted">@{profile.handle}</span>
        </h1>
        <p className="text-sm text-muted">
          账号类型：{profile.account_kind === "organisation" ? "组织" : "个人"}
        </p>
      </header>

      <div className="grid gap-4 sm:grid-cols-3">
        {EMPTY_SECTIONS.map((section) => (
          <section
            key={section.title}
            className="flex flex-col gap-2 rounded-lg border border-line bg-surface p-4"
          >
            <h2 className="font-medium">{section.title}</h2>
            <p className="text-sm text-muted">{section.hint}</p>
          </section>
        ))}
      </div>
    </main>
  );
}
