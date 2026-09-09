import { LoginForm } from "./login-form";

export const metadata = { title: "登录 — ArtLink" };

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ next?: string }>;
}) {
  const params = await searchParams;
  // Only same-site relative paths, never an off-site redirect target.
  const nextPath = params.next?.startsWith("/") ? params.next : "/dashboard";

  return (
    <main className="mx-auto flex w-full max-w-5xl flex-col items-center gap-6 px-4 py-12">
      <h1 className="text-2xl font-semibold">登录 ArtLink</h1>
      <LoginForm nextPath={nextPath} />
    </main>
  );
}
