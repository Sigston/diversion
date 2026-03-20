import { defineConfig } from 'vite'

export default defineConfig({
  // base tells Vite the path where the app will be served from.
  // Without this, Vite generates asset paths like /assets/main.js,
  // which would look in the server root instead of /game/assets/main.js.
  // This must match the directory on the server where the built files live.
  base: '/game/',
})
