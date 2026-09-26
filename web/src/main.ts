import '@fontsource-variable/inter';
import '@fontsource-variable/fraunces';
import './app.css';
import { mount } from 'svelte';
import App from './App.svelte';
import { dropConnection, game } from './lib/game.svelte';
import { setPictureResolver } from './lib/markdown';
import { pictureUrl } from './lib/art';

// a note's pictures: those the table uploaded, and the packs' own
setPictureResolver(pictureUrl);

mount(App, { target: document.getElementById('app')! });
// what this screen knows, for a look from the browser's console (and the tests)
(window as unknown as { hexmap: unknown }).hexmap = { game, drop: dropConnection };
