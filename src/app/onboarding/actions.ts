"use server";

import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { handleProblem, isValidAccountKind } from "@/lib/onboarding";

export type OnboardingState = { error: string | null };

/**
 * Completes onboarding: account kind + category + handle on the
 * caller's own profile row. Authorization via getUser() (server
 * verified); the profiles RLS "own row" policy enforces the rest.
 */
export async function completeOnboarding(
  _prev: OnboardingState,
  formData: FormData,
): Promise<OnboardingState> {
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const handle = String(formData.get("handle") ?? "");
  const kind = String(formData.get("accountKind") ?? "");
  const categoryId = Number(formData.get("categoryId"));

  const problem = handleProblem(handle);
  if (problem) return { error: problem };
  if (!isValidAccountKind(kind)) return { error: "请选择账号类型" };
  if (!Number.isInteger(categoryId) || categoryId <= 0) {
    return { error: "请选择类目" };
  }

  const { error } = await supabase
    .from("profiles")
    .update({ handle, account_kind: kind, category_id: categoryId })
    .eq("id", user.id);

  if (error) {
    if (error.code === "23505") {
      return { error: "这个 handle 刚被别人占了，换一个试试" };
    }
    return { error: error.message };
  }

  redirect("/dashboard");
}
