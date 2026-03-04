/** @type {import('tailwindcss').Config} */
export default {
    content: [
        "./index.html",
        "./src/**/*.{js,ts,jsx,tsx}",
    ],
    theme: {
        extend: {
            colors: {
                primary: "#1E3A8A",
                secondary: "#3B82F6",
            },
            fontFamily: {
                tajawal: ['Tajawal', 'sans-serif']
            }
        },
    },
    plugins: [],
}
