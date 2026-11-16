import { connectPort } from "./slack/extension/background.mjs";

chrome.runtime.onConnect.addListener(connectPort);
