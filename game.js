'use strict';
// ===== 움직임 · 스킬 테스트 =====
const TILE = 16, COLS = 20, ROWS = 15, VW = COLS * TILE, VH = ROWS * TILE;
const canvas = document.getElementById('game');
const ctx = canvas.getContext('2d');

// 화면을 정수배로 확대
function resize() {
  const s = Math.max(1, Math.floor(Math.min(innerWidth / VW, (innerHeight - 40) / VH)));
  canvas.style.width = VW * s + 'px';
  canvas.style.height = VH * s + 'px';
}
addEventListener('resize', resize); resize();

// ---------- 입력 ----------
const keys = new Set(), pressed = new Set();
const KEYMAP = { ArrowUp: 'up', KeyW: 'up', ArrowDown: 'down', KeyS: 'down', ArrowLeft: 'left', KeyA: 'left',
  ArrowRight: 'right', KeyD: 'right', Space: 'attack', KeyZ: 'attack', KeyX: 'dash', KeyC: 'fire' };
addEventListener('keydown', e => {
  const k = KEYMAP[e.code]; if (!k) return;
  e.preventDefault();
  if (!keys.has(k)) pressed.add(k);
  keys.add(k);
});
addEventListener('keyup', e => { const k = KEYMAP[e.code]; if (k) keys.delete(k); });
addEventListener('blur', () => keys.clear());

// ---------- 맵: 테두리만 나무인 빈 풀밭 ----------
const map = [];
for (let y = 0; y < ROWS; y++) for (let x = 0; x < COLS; x++)
  map.push(x === 0 || y === 0 || x === COLS - 1 || y === ROWS - 1 ? 'T' : '.');
const solidAt = (px, py) => {
  const tx = Math.floor(px / TILE), ty = Math.floor(py / TILE);
  if (tx < 0 || ty < 0 || tx >= COLS || ty >= ROWS) return true;
  return map[ty * COLS + tx] === 'T';
};

// 시드 난수 (풀 무늬 고정용)
function rng(seed) { let s = seed || 1; return () => (s = (s * 16807) % 2147483647) / 2147483647; }

// 배경을 한 번만 그려 둔다
const bg = document.createElement('canvas'); bg.width = VW; bg.height = VH;
(() => {
  const g = bg.getContext('2d');
  for (let ty = 0; ty < ROWS; ty++) for (let tx = 0; tx < COLS; tx++) {
    const x = tx * TILE, y = ty * TILE, r = rng(tx * 97 + ty * 31 + 7);
    g.fillStyle = '#5fae3e'; g.fillRect(x, y, TILE, TILE);
    for (let i = 0; i < 6; i++) {
      g.fillStyle = r() < .5 ? '#4f9a34' : '#76c450';
      g.fillRect(x + Math.floor(r() * 15), y + Math.floor(r() * 14), 1, 2);
    }
    if (map[ty * COLS + tx] === 'T') {
      g.fillStyle = '#6b4423'; g.fillRect(x + 6, y + 11, 4, 4);
      g.fillStyle = '#245322'; g.fillRect(x + 1, y + 3, 14, 8); g.fillRect(x + 3, y + 1, 10, 11);
      g.fillStyle = '#2f6b2a'; g.fillRect(x + 2, y + 3, 12, 6); g.fillRect(x + 4, y + 2, 8, 8);
      g.fillStyle = '#3f8a35'; g.fillRect(x + 4, y + 3, 5, 3);
    }
  }
})();

// ---------- 캐릭터 도트 ----------
const PAL = { hair: '#5a3420', skin: '#f2c49b', shirt: '#2f7fd1', pants: '#3b3355', dark: '#1e1a2b' };
const spriteCache = {};
function charSprite(dir, frame) {
  const key = dir + frame;
  if (spriteCache[key]) return spriteCache[key];
  const c = document.createElement('canvas'); c.width = c.height = 16;
  const g = c.getContext('2d');
  const R = (col, x, y, w, h) => { g.fillStyle = PAL[col] || col; g.fillRect(x, y, w, h); };
  const side = dir === 'left' || dir === 'right';
  if (dir === 'left') { g.translate(16, 0); g.scale(-1, 1); }
  // 다리 (걷기 프레임 0~3)
  const step = frame % 2 === 1 ? (frame === 1 ? 1 : -1) : 0;
  if (side) {
    R('pants', 6 + step, 12, 2, 3); R('pants', 8 - step, 12, 2, 3);
    R('dark', 6 + step, 15, 2, 1); R('dark', 8 - step, 15, 2, 1);
  } else {
    R('pants', 5, 12, 2, 3 - Math.max(0, step)); R('pants', 9, 12, 2, 3 + Math.min(0, step));
    R('dark', 5, 15 - Math.max(0, step), 2, 1); R('dark', 9, 15 + Math.min(0, step), 2, 1);
  }
  // 몸통
  if (side) { R('shirt', 5, 8, 6, 5); R('skin', 7 - step, 10, 2, 2); R('dark', 5, 12, 6, 1); }
  else { R('shirt', 4, 8, 8, 4); R('shirt', 3, 9, 1, 2); R('shirt', 12, 9, 1, 2);
    R('skin', 3, 11, 1, 1); R('skin', 12, 11, 1, 1); R('dark', 4, 11, 8, 1); }
  // 머리
  R('hair', 4, 1, 8, 2); R('hair', 3, 2, 10, 3);
  if (dir === 'down') {
    R('skin', 4, 4, 8, 4); R('hair', 3, 4, 1, 3); R('hair', 12, 4, 1, 3); R('hair', 4, 4, 8, 1);
    R('dark', 6, 5, 1, 2); R('dark', 9, 5, 1, 2);
  } else if (dir === 'up') {
    R('hair', 3, 4, 10, 4);
  } else {
    R('skin', 6, 4, 6, 4); R('hair', 3, 4, 4, 3); R('hair', 6, 4, 6, 1); R('dark', 10, 5, 1, 2);
  }
  return (spriteCache[key] = c);
}

// ---------- 이미지 캐릭터 스프라이트 (20×54px, 발 위치 고정) ----------
// 원본은 오른쪽을 보므로, 왼쪽을 볼 때 좌우 반전한다.
const ANIM = {
  idle: { frames: 6, ms: 160 },  // 숨쉬기 + 머리카락·스카프 흔들림
  walk: { frames: 8, ms: 85 },   // 앞으로 기울인 달리기
};
const SPRITE_W = 48, SPRITE_FEET = 46; // 발바닥이 닿는 행 (위에서부터)
const sprites = {};
for (const name in ANIM) {
  sprites[name] = [];
  for (let i = 1; i <= ANIM[name].frames; i++) {
    const img = new Image();
    img.src = `assets/character/${name}/${name}_${i}.png`;
    sprites[name].push(img);
  }
}
const spriteReady = img => img.complete && img.naturalWidth > 0;

// ---------- 게임 상태 ----------
const DIRS = { up: [0, -1], down: [0, 1], left: [-1, 0], right: [1, 0] };
const player = {
  x: VW / 2, y: VH / 2, dir: 'down', anim: 0, speed: 80,
  state: 'idle', stateT: 0, facing: 'right',
  attackT: 0, dashT: 0, dashVX: 0, dashVY: 0,
  cd: { attack: 0, dash: 0, fire: 0 },
};
const SKILLS = {
  attack: { name: '베기', cd: 0.35, color: '#e6e6e6', key: 'Z' },
  dash:   { name: '대시', cd: 1.0,  color: '#7fd7ff', key: 'X' },
  fire:   { name: '파이어볼', cd: 0.8, color: '#ff8a3d', key: 'C' },
};
const dummy = { x: VW / 2 + 64, y: VH / 2, hitT: 0, hits: 0 };
const projectiles = [], particles = [], afterimages = [], texts = [];
const HB = 5; // 캐릭터 발밑 충돌 반경

function moveWithCollision(o, dx, dy) {
  const blocked = (x, y) => solidAt(x - HB, y - HB) || solidAt(x + HB, y - HB) ||
    solidAt(x - HB, y + HB) || solidAt(x + HB, y + HB) || Math.hypot(x - dummy.x, y - dummy.y) < 10;
  if (!blocked(o.x + dx, o.y)) o.x += dx;
  if (!blocked(o.x, o.y + dy)) o.y += dy;
}

function burst(x, y, color, n, speed) {
  for (let i = 0; i < n; i++) {
    const a = Math.random() * Math.PI * 2, s = speed * (0.4 + Math.random() * 0.6);
    particles.push({ x, y, vx: Math.cos(a) * s, vy: Math.sin(a) * s, life: 0.3 + Math.random() * 0.3, color });
  }
}
function hitDummy(dmg, color) {
  dummy.hitT = 0.15; dummy.hits++;
  burst(dummy.x, dummy.y - 6, color, 8, 60);
  texts.push({ x: dummy.x, y: dummy.y - 16, t: 0.7, s: String(dmg) });
}

function update(dt) {
  const p = player;
  for (const k in p.cd) p.cd[k] = Math.max(0, p.cd[k] - dt);

  // 이동 입력
  let ix = (keys.has('right') ? 1 : 0) - (keys.has('left') ? 1 : 0);
  let iy = (keys.has('down') ? 1 : 0) - (keys.has('up') ? 1 : 0);
  if (ix || iy) {
    // 마지막으로 누른 축을 바라보도록: 대각선이면 기존 방향 유지
    const cand = [];
    if (ix) cand.push(ix > 0 ? 'right' : 'left');
    if (iy) cand.push(iy > 0 ? 'down' : 'up');
    if (p.attackT <= 0 && !cand.includes(p.dir)) p.dir = cand[0];
    if (ix) p.facing = ix > 0 ? 'right' : 'left'; // 위/아래 이동 시엔 좌우 방향 유지
  }
  // 애니메이션 상태: 바뀌면 1번 프레임부터
  const next = ix || iy || p.dashT > 0 ? 'walk' : 'idle';
  if (next !== p.state) { p.state = next; p.stateT = 0; } else p.stateT += dt;

  // 스킬
  if (pressed.has('attack') && p.cd.attack <= 0 && p.dashT <= 0) {
    p.cd.attack = SKILLS.attack.cd; p.attackT = 0.18;
    const [dx, dy] = DIRS[p.dir];
    const hx = p.x + dx * 14, hy = p.y - 4 + dy * 14;
    if (Math.hypot(hx - dummy.x, hy - (dummy.y - 6)) < 16) hitDummy(1, '#ffffff');
  }
  if (pressed.has('dash') && p.cd.dash <= 0) {
    p.cd.dash = SKILLS.dash.cd; p.dashT = 0.15;
    let vx = ix, vy = iy;
    if (!vx && !vy) [vx, vy] = DIRS[p.dir];
    const l = Math.hypot(vx, vy); p.dashVX = vx / l * 320; p.dashVY = vy / l * 320;
    burst(p.x, p.y, '#cfefff', 6, 40);
  }
  if (pressed.has('fire') && p.cd.fire <= 0) {
    p.cd.fire = SKILLS.fire.cd;
    const [dx, dy] = DIRS[p.dir];
    projectiles.push({ x: p.x + dx * 8, y: p.y - 5 + dy * 8, vx: dx * 180, vy: dy * 180, life: 1.2 });
  }
  pressed.clear();

  // 이동 처리
  if (p.dashT > 0) {
    p.dashT -= dt;
    afterimages.push({ x: p.x, y: p.y, dir: p.dir, facing: p.facing, t: 0.2 });
    moveWithCollision(p, p.dashVX * dt, p.dashVY * dt);
  } else if (ix || iy) {
    const l = Math.hypot(ix, iy), sp = p.speed * (p.attackT > 0 ? 0.4 : 1);
    moveWithCollision(p, ix / l * sp * dt, iy / l * sp * dt);
    p.anim += dt * 8;
  } else p.anim = 0;
  p.attackT = Math.max(0, p.attackT - dt);

  // 파이어볼
  for (const f of projectiles) {
    f.x += f.vx * dt; f.y += f.vy * dt; f.life -= dt;
    if (Math.random() < .6) particles.push({ x: f.x, y: f.y, vx: (Math.random() - .5) * 20, vy: -10 - Math.random() * 20,
      life: .25, color: Math.random() < .5 ? '#ffd24a' : '#ff6a2a' });
    if (Math.hypot(f.x - dummy.x, f.y - (dummy.y - 6)) < 10) { hitDummy(3, '#ff8a3d'); f.life = 0; }
    else if (solidAt(f.x, f.y)) { burst(f.x, f.y, '#ff8a3d', 10, 50); f.life = 0; }
  }
  remove(projectiles, f => f.life <= 0);
  for (const q of particles) { q.x += q.vx * dt; q.y += q.vy * dt; q.life -= dt; }
  remove(particles, q => q.life <= 0);
  for (const a of afterimages) a.t -= dt;
  remove(afterimages, a => a.t <= 0);
  for (const t of texts) { t.t -= dt; t.y -= 20 * dt; }
  remove(texts, t => t.t <= 0);
  dummy.hitT = Math.max(0, dummy.hitT - dt);
}
function remove(arr, fn) { for (let i = arr.length - 1; i >= 0; i--) if (fn(arr[i])) arr.splice(i, 1); }

// ---------- 그리기 ----------
const frameOf = p => (p.anim ? Math.floor(p.anim) % 4 : 0);
function drawChar(x, y, dir, frame, state = 'idle', t = 0, facing = 'right') {
  const a = ANIM[state], img = sprites[state][Math.floor(t * 1000 / a.ms) % a.frames];
  if (!spriteReady(img)) { // 이미지 로딩 전에는 기존 도트 캐릭터
    ctx.drawImage(charSprite(dir, frame), Math.round(x - 8), Math.round(y - 14)); return;
  }
  const dx = Math.round(x - SPRITE_W / 2), dy = Math.round(y - SPRITE_FEET);
  if (facing === 'left') {
    ctx.save(); ctx.translate(dx + SPRITE_W, dy); ctx.scale(-1, 1); ctx.drawImage(img, 0, 0); ctx.restore();
  } else ctx.drawImage(img, dx, dy);
}
function shadow(x, y) { ctx.fillStyle = 'rgba(0,0,0,.25)'; ctx.fillRect(Math.round(x - 5), Math.round(y + 1), 10, 2); }

function drawDummy() {
  const x = Math.round(dummy.x), y = Math.round(dummy.y);
  const shake = dummy.hitT > 0 ? (Math.random() < .5 ? -1 : 1) : 0;
  shadow(x, y);
  ctx.fillStyle = '#7a522a'; ctx.fillRect(x - 1, y - 10, 2, 11);
  ctx.fillStyle = dummy.hitT > 0 ? '#fff' : '#c9a36a';
  ctx.fillRect(x - 6 + shake, y - 10, 12, 3); ctx.fillRect(x - 3 + shake, y - 16, 6, 6);
  ctx.fillStyle = '#8a3b2a'; ctx.fillRect(x - 3 + shake, y - 13, 6, 1);
}

function drawSlash() {
  const p = player, [dx, dy] = DIRS[p.dir];
  const t = 1 - p.attackT / 0.18;           // 0 → 1
  const base = Math.atan2(dy, dx), a = base - 1.2 + t * 2.4;
  const cx = p.x, cy = p.y - 17; // 캐릭터 몸통 높이
  ctx.strokeStyle = 'rgba(255,255,255,.5)'; ctx.lineWidth = 3;
  ctx.beginPath(); ctx.arc(cx, cy, 13, base - 1.2, a); ctx.stroke();
  ctx.fillStyle = '#e6e6e6';
  for (let r = 4; r <= 14; r++) ctx.fillRect(Math.round(cx + Math.cos(a) * r), Math.round(cy + Math.sin(a) * r), 1, 1);
  ctx.fillStyle = '#c8a040'; ctx.fillRect(Math.round(cx + Math.cos(a) * 4) - 1, Math.round(cy + Math.sin(a) * 4) - 1, 2, 2);
}

function drawHUD() {
  let x = 4;
  for (const k of ['attack', 'dash', 'fire']) {
    const s = SKILLS[k], ratio = player.cd[k] / s.cd;
    ctx.fillStyle = 'rgba(0,0,0,.6)'; ctx.fillRect(x, VH - 18, 56, 14);
    ctx.fillStyle = s.color; ctx.fillRect(x + 1, VH - 17, Math.round(54 * (1 - ratio)), 12);
    ctx.fillStyle = ratio > 0 ? '#fff' : '#000'; ctx.font = '8px monospace'; ctx.textBaseline = 'middle';
    ctx.fillText(s.key + ' ' + s.name, x + 3, VH - 11);
    x += 60;
  }
  ctx.fillStyle = '#fff'; ctx.fillText('허수아비 타격: ' + dummy.hits, 4, 8);
}

function render() {
  ctx.imageSmoothingEnabled = false;
  ctx.drawImage(bg, 0, 0);
  for (const a of afterimages) { ctx.globalAlpha = a.t / 0.2 * 0.5; drawChar(a.x, a.y, a.dir, 0, 'idle', 0, a.facing); }
  ctx.globalAlpha = 1;
  // y 순서대로 그리기
  const list = [{ y: dummy.y, d: drawDummy }, { y: player.y, d: () => {
    shadow(player.x, player.y);
    if (player.attackT > 0 && player.dir === 'up') drawSlash();
    drawChar(player.x, player.y, player.dir, frameOf(player), player.state, player.stateT, player.facing);
    if (player.attackT > 0 && player.dir !== 'up') drawSlash();
  } }];
  list.sort((a, b) => a.y - b.y).forEach(o => o.d());
  for (const f of projectiles) {
    ctx.fillStyle = '#ff6a2a'; ctx.fillRect(Math.round(f.x) - 3, Math.round(f.y) - 3, 6, 6);
    ctx.fillStyle = '#ffe27a'; ctx.fillRect(Math.round(f.x) - 1, Math.round(f.y) - 1, 3, 3);
  }
  for (const q of particles) { ctx.fillStyle = q.color; ctx.fillRect(Math.round(q.x), Math.round(q.y), 1, 1); }
  ctx.font = '8px monospace'; ctx.textAlign = 'center';
  for (const t of texts) { ctx.fillStyle = '#000'; ctx.fillText(t.s, t.x + 1, t.y + 1); ctx.fillStyle = '#ffe27a'; ctx.fillText(t.s, t.x, t.y); }
  ctx.textAlign = 'left';
  drawHUD();
}

// ---------- 루프 (고정 60fps 업데이트) ----------
let last = performance.now(), acc = 0;
function loop(now) {
  acc += Math.min(0.25, (now - last) / 1000); last = now;
  while (acc >= 1 / 60) { update(1 / 60); acc -= 1 / 60; }
  render();
  requestAnimationFrame(loop);
}
requestAnimationFrame(loop);
