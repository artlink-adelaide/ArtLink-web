import { ResetPasswordForm } from "./reset-password-form";

export const metadata = { title: "设置新密码 — ArtLink" };

export default function ResetPasswordPage() {
  return (
    <main className="mx-auto flex w-full max-w-5xl flex-col items-center gap-6 px-4 py-12">
      <h1 className="text-2xl font-semibold">设置新密码</h1>
      <ResetPasswordForm />
    </main>
  );
}
