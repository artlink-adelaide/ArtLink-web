import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'node',
    include: ['tests/**/*.spec.ts', 'src/**/*.spec.ts'],
    // No tests exist yet. Remove this once the first access-rule test lands
    // (evaluation criterion E2) so an empty suite can no longer pass CI.
    passWithNoTests: true,
  },
})
