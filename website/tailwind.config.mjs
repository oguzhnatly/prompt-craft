/** @type {import('tailwindcss').Config} */
export default {
  content: ['./src/**/*.{astro,html,js,jsx,md,mdx,svelte,ts,tsx,vue}'],
  theme: {
    extend: {
      colors: {
        void: '#07080B',
        surface: '#0D0F14',
        panel: '#111318',
        border: '#1E2130',
        teal: {
          DEFAULT: '#00FFB2',
          dim: '#00C98A',
          ghost: 'rgba(0,255,178,0.08)',
          glow: 'rgba(0,255,178,0.18)',
        },
        ink: {
          DEFAULT: '#F0F6FC',
          secondary: '#8892A4',
          muted: '#4A5568',
          code: '#A8F0D0',
        },
      },
      fontFamily: {
        sans: ['Geist', 'Inter', 'system-ui', 'sans-serif'],
        mono: ['JetBrains Mono', 'Fira Code', 'monospace'],
      },
      backgroundImage: {
        'grid': `linear-gradient(rgba(0,255,178,0.035) 1px, transparent 1px), linear-gradient(90deg, rgba(0,255,178,0.035) 1px, transparent 1px)`,
        'grid-dense': `linear-gradient(rgba(0,255,178,0.06) 1px, transparent 1px), linear-gradient(90deg, rgba(0,255,178,0.06) 1px, transparent 1px)`,
        'hero-glow': 'radial-gradient(ellipse 80% 60% at 50% 0%, rgba(0,255,178,0.07) 0%, transparent 70%)',
        'teal-glow': 'radial-gradient(circle at center, rgba(0,255,178,0.15) 0%, transparent 70%)',
      },
      backgroundSize: {
        'grid': '64px 64px',
        'grid-dense': '32px 32px',
      },
      animation: {
        'scan': 'scan 2.4s ease-in-out infinite',
        'pulse-teal': 'pulse-teal 2s ease-in-out infinite',
        'fade-up': 'fade-up 0.6s ease forwards',
        'blink': 'blink 1.1s step-end infinite',
        'flow': 'flow 3s ease-in-out infinite',
      },
      keyframes: {
        scan: {
          '0%, 100%': { transform: 'translateY(0)', opacity: '0' },
          '10%': { opacity: '1' },
          '90%': { opacity: '1' },
          '100%': { transform: 'translateY(100%)', opacity: '0' },
        },
        'pulse-teal': {
          '0%, 100%': { boxShadow: '0 0 0 0 rgba(0,255,178,0)' },
          '50%': { boxShadow: '0 0 20px 4px rgba(0,255,178,0.2)' },
        },
        'fade-up': {
          from: { opacity: '0', transform: 'translateY(24px)' },
          to: { opacity: '1', transform: 'translateY(0)' },
        },
        blink: {
          '0%, 100%': { opacity: '1' },
          '50%': { opacity: '0' },
        },
        flow: {
          '0%, 100%': { transform: 'translateX(0) scaleX(1)' },
          '50%': { transform: 'translateX(4px) scaleX(1.02)' },
        },
      },
    },
  },
  plugins: [],
};
