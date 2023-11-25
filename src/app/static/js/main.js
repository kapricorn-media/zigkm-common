import {wasmInit} from '/js/wasm.js';

function _documentOnLoad()
{
    console.log("_documentOnLoad");

    const memoryBytes = 512 * 1024;
    wasmInit("/main.wasm", memoryBytes);
}

export {
    _documentOnLoad
};
