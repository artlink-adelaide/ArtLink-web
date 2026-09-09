import { RegisterForm } from "./register-form";

export const metadata = { title: "注册 — ArtLink" };

export default function RegisterPage() {
  return (
    <main className="mx-auto flex w-full max-w-5xl flex-col items-center gap-6 px-4 py-12">
      <h1 className="text-2xl font-semibold">注册 ArtLink</h1>
      <RegisterForm />
    </main>
  );
}
