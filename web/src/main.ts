import '@fontsource-variable/inter';
import '@fontsource-variable/fraunces';
import './app.css';
import { mount } from 'svelte';
import App from './App.svelte';
import { game } from './lib/game.svelte';

mount(App, { target: document.getElementById('app')! });
// what this screen knows, for a look from the browser's console (and the tests)
(window as unknown as { hexmap: unknown }).hexmap = { game };
