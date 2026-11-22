import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { test } from 'node:test';

const utils = vm.createContext({});
vm.runInContext(readFileSync(new URL('../StreamUtils.js', import.meta.url), 'utf8').replace(/^\.pragma library\s*/, ''), utils);

test('preserves RTSPS tokens, encoded credentials, query flags, and IPv6', () => {
    for (const url of [
        'rtsps://10.0.0.5:7441/opaqueToken?enableSrtp',
        'rtsp://user:p%40ss@camera.lan:554/stream?profile=main&video=1',
        'rtsps://[2001:db8::1]:7441/live',
    ]) {
        assert.equal(utils.validateCamera('Driveway', url), '');
        assert.equal(utils.normalizeCameras([{name: 'Driveway', url}])[0].url, url);
    }
});

test('rejects missing names, hosts, unsupported schemes and whitespace', () => {
    for (const url of ['', 'https://camera/live', 'file:///etc/passwd', 'rtsp://', 'rtsp:///live', 'rtsp://camera/live\nsecret', 'rtsp://camera/a b'])
        assert.notEqual(utils.validateCamera('Camera', url), '');
    assert.notEqual(utils.validateCamera('  ', 'rtsp://camera/live'), '');
});

test('normalizes malformed settings and duplicate IDs without restoring deleted cameras', () => {
    assert.equal(utils.normalizeCameras(null).length, 0);
    assert.equal(utils.normalizeCameras([]).length, 0);
    const cameras = utils.normalizeCameras([null, { id:'__proto__', name:' A ', url:'rtsp://a/live' }, { id:'__proto__', name:'B',url:'rtsp://b/live' }]);
    assert.equal(cameras.length, 2);
    assert.equal(cameras[0].name, 'A');
    assert.notEqual(cameras[0].id, cameras[1].id);
    assert.equal(utils.selectedCamera(cameras, 'deleted').id, cameras[0].id);
    assert.equal(utils.selectedCamera([], 'deleted'), null);
});

test('external playback uses argument boundaries and preserves shell metacharacters as data', () => {
    const camera = { name:'$(touch /tmp/never)', url:'rtsps://camera/a;$(id)?enableSrtp&x=1' };
    const args = utils.mpvArguments(camera, true);
    assert.equal(args[0], 'mpv');
    assert.equal(args.at(-2), '--');
    assert.equal(args.at(-1), camera.url);
    assert.ok(args.includes('--title=' + camera.name));
    assert.ok(args.includes('--mute=yes'));
    assert.ok(!args.includes('sh'));
});
