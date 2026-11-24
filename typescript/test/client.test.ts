import assert from 'node:assert/strict';
import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';
import type { AddressInfo, Socket } from 'node:net';
import { after, before, beforeEach, describe, test } from 'node:test';
import { gzipSync } from 'node:zlib';

import {
  Food,
  FoodApiBadRequest,
  FoodApiCancelledError,
  FoodApiClient,
  FoodApiError,
  FoodApiForbidden,
  FoodApiHttpError,
  FoodApiInvalidInput,
  FoodApiNetworkError,
  FoodApiNotFound,
  FoodApiRateLimited,
  FoodApiServerError,
  FoodApiTimeoutError,
  FoodApiUnauthorized,
  FoodApiUnavailable,
  FoodType,
  ImageMatch,
  ImageTier,
  NutrientFlag,
  sdkVersion,
  type FoodApiClientOptions,
} from '../dist/index.js';

const foodJson = `{"id":"01a163d2-bfdc-7912-878d-4020b11915ab","name":"Cola","brand":null,"type":"generic","barcodes":[],
 "servings":[{"description":"100 g","measurement":"g","metric_amount":100,"metric_unit":"g","units":100,
   "nutrients":{"calories":37,"protein":0,"sugar":0.5,"fiber":null,"cnf_409":0.01}},
  {"description":"1 fl oz","measurement":"fl oz","metric_amount":29.57,"metric_unit":"ml","units":1,"generic":true,
   "nutrients":{"calories":10.94}}],
 "source":{"provider":"CNF","id":"2920"},"ingredients":null,"category":"Beverages",
 "attributes":{"alternate_names":"pop, soda, soft drink"},"nutrient_flags":{"sugar":"upper_bound","fat":"something_new"}}`;

const withImage = (image: string) => foodJson.replace('"nutrient_flags"', `"image":${image},"nutrient_flags"`);

type Handler = (req: IncomingMessage, res: ServerResponse) => void;

/** A local API server: each test sets `handler` and reads `requests`. */
let handler: Handler;
let requests: IncomingMessage[];
let baseUrl: string;
const server = createServer((req, res) => {
  requests.push(req);
  handler(req, res);
});
const sockets = new Set<Socket>();
server.on('connection', (s) => {
  sockets.add(s);
  s.on('close', () => sockets.delete(s));
});

before(async () => {
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  baseUrl = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});
after(() => {
  for (const s of sockets) s.destroy();
  server.close();
});
beforeEach(() => {
  requests = [];
  handler = () => assert.fail('no handler set');
});

function reply(res: ServerResponse, status: number, body: string, headers: Record<string, string> = {}) {
  res.writeHead(status, { 'Content-Type': 'application/json', ...headers });
  res.end(body);
}

function client(options: Partial<FoodApiClientOptions> = {}) {
  return new FoodApiClient({ apiKey: 'test-key', baseUrl, userAgent: 'my-app/1.0', timeout: 5000, ...options });
}

const query = (req: IncomingMessage) => new URL(req.url ?? '', 'http://x').searchParams;

describe('search', () => {
  test('sends the query and key and parses the page', async () => {
    handler = (_, res) =>
      reply(
        res,
        200,
        `{"data":[${foodJson}],"meta":{"query":"cola zero","page":2,"limit":5,"total":11,"source":"catalog"}}`,
        { 'X-Cache': 'HIT' },
      );
    const page = await client().search('Cola  Zero', { page: 2, limit: 5 });

    const req = requests[0]!;
    assert.equal(requests.length, 1);
    assert.equal(new URL(req.url!, 'http://x').pathname, '/v2/foods/search');
    assert.deepEqual(Object.fromEntries(query(req)), { q: 'Cola  Zero', page: '2', limit: '5' });
    assert.equal(req.headers['authorization'], 'Bearer test-key');
    assert.equal(req.headers['accept'], 'application/json');
    assert.equal(req.headers['user-agent'], `my-app/1.0 studio93-food-api-ts/${sdkVersion}`);
    assert.equal(req.headers['x-client-ip'], undefined);

    assert.equal(page.query, 'cola zero');
    assert.equal(page.page, 2);
    assert.equal(page.limit, 5);
    assert.equal(page.total, 11);
    assert.equal(page.source, 'catalog');
    assert.equal(page.cached, true);
    assert.equal(page.region, null, 'no country ranked first');
    assert.equal(page.brand, null);

    const food = page.foods[0]!;
    assert.equal(page.foods.length, 1);
    assert.ok(food instanceof Food);
    assert.equal(food.id, '01a163d2-bfdc-7912-878d-4020b11915ab');
    assert.equal(food.name, 'Cola');
    assert.equal(food.brand, null);
    assert.equal(food.type, FoodType.generic);
    assert.deepEqual(food.barcodes, []);
    assert.deepEqual(food.source, { provider: 'CNF', id: '2920' });
    assert.equal(food.ingredients, null);
    assert.equal(food.category, 'Beverages');
    assert.deepEqual(
      food.servings.map((s) => s.generic),
      [false, true],
    );
    const [first, generic] = food.servings;
    assert.equal(first!.description, '100 g');
    assert.equal(first!.metricAmount, 100);
    assert.equal(first!.metricUnit, 'g');
    assert.equal(first!.units, 100);
    assert.equal(first!.sourceId, null);
    assert.equal(generic!.measurement, 'fl oz');
    assert.equal(generic!.nutrients.calories, 10.94);
    assert.equal(generic!.nutrients.protein, null, 'a nutrient the serving lacks is null');

    const n = first!.nutrients;
    assert.equal(n.calories, 37);
    assert.equal(n.protein, 0);
    assert.equal(n.fiber, null, 'unknown values are null');
    assert.equal(n.get('cnf_409'), 0.01);
    assert.equal(n.get('toString'), null);

    assert.equal(food.flag('sugar'), NutrientFlag.upperBound);
    assert.equal(food.flag('fat'), NutrientFlag.unknown, 'flags newer than the SDK still parse');
    assert.equal(food.flag('protein'), null);
    assert.deepEqual(food.alternateNames, ['pop', 'soda', 'soft drink']);
    assert.equal(food.image, null, 'answers from before images still parse');
  });

  test('sends no page or limit unless given, and reports the region and brand', async () => {
    handler = (_, res) =>
      reply(
        res,
        200,
        '{"data":[],"meta":{"query":"coke","page":0,"limit":20,"total":0,"source":"catalog","region":"CA","brand":"Coca-Cola"}}',
      );
    const page = await client().search('coke');
    assert.deepEqual(Object.fromEntries(query(requests[0]!)), { q: 'coke' });
    assert.equal(page.region, 'CA');
    assert.equal(page.brand, 'Coca-Cola');
    assert.equal(page.cached, false);
    assert.deepEqual(page.foods, []);
  });

  test('empty results are empty lists', async () => {
    handler = (_, res) => reply(res, 200, '{"data":null,"meta":{"total":0}}');
    assert.deepEqual((await client().search('xqzw')).foods, []);
    const ac = await client().autocomplete('xq');
    assert.deepEqual(ac.suggestions, []);
    assert.equal(ac.query, 'xq');
    assert.equal(ac.limit, 8);
  });
});

test('autocomplete sends the query and limit and parses suggestions', async () => {
  handler = (_, res) =>
    reply(
      res,
      200,
      '{"data":[{"id":"a1","name":"Chicken breast","brand":null},{"id":"b2","name":"Chicken nuggets","brand":"Acme"}],"meta":{"query":"chick","limit":5,"total":240}}',
      { 'X-Cache': 'HIT' },
    );
  const ac = await client().autocomplete('chick', { limit: 5 });
  assert.equal(new URL(requests[0]!.url!, 'http://x').pathname, '/v2/foods/autocomplete');
  assert.deepEqual(Object.fromEntries(query(requests[0]!)), { q: 'chick', limit: '5' });
  assert.deepEqual(ac.suggestions, [
    { id: 'a1', name: 'Chicken breast', brand: null },
    { id: 'b2', name: 'Chicken nuggets', brand: 'Acme' },
  ]);
  assert.equal(ac.total, 240);
  assert.equal(ac.limit, 5);
  assert.equal(ac.cached, true);
});

test('foods carry their image', async () => {
  handler = (req, res) => {
    switch (req.url) {
      case '/v2/foods/cheddar':
        return reply(
          res,
          200,
          `{"data":${withImage('{"key":"dairy/cheddar","url":"https://images.example.com/dairy/cheddar.jpg","match":"food"}')}}`,
        );
      case '/v2/foods/barcode/3017624010701':
        return reply(
          res,
          200,
          `{"data":${withImage('{"key":"generic/plate","url":"https://images.example.com/generic/plate.jpg","match":"fallback"}')}}`,
        );
      default:
        return reply(
          res,
          200,
          `{"data":${withImage('{"key":"dairy/cheese","url":"https://images.example.com/dairy/cheese.jpg","match":"something_new"}')}}`,
        );
    }
  };
  const c = client();
  const image = (await c.food('cheddar')).image!;
  assert.equal(image.key, 'dairy/cheddar');
  assert.equal(image.url, 'https://images.example.com/dairy/cheddar.jpg');
  assert.equal(image.match, ImageMatch.food);
  assert.equal(image.isFallback, false);

  assert.equal((await c.foodByBarcode('3017624010701')).image!.isFallback, true);

  const newer = (await c.food('gouda')).image!;
  assert.equal(newer.match, ImageMatch.unknown, 'matches newer than the SDK still parse');
  assert.equal(newer.isFallback, false);
});

test('a food stored as JSON reads back the same', async () => {
  handler = (_, res) =>
    reply(
      res,
      200,
      `{"data":${withImage('{"key":"drinks/cola","url":"https://images.example.com/drinks/cola.jpg","match":"food"}')}}`,
    );
  const food = await client().food('cola');
  const text = JSON.stringify(food);
  assert.equal(JSON.parse(text).nutrient_flags.sugar, 'upper_bound', 'stored in the API form');
  const again = Food.fromJson(JSON.parse(text));
  assert.deepEqual(again, food);
  assert.equal(again.servings[0]!.nutrients.calories, 37);
  assert.equal(again.image!.match, ImageMatch.food);
});

test('the image set parses', async () => {
  handler = (_, res) =>
    reply(
      res,
      200,
      `{"data":{"version":1,"updated":"2026-11-17","fallback":"generic/plate",
 "groups":[{"key":"dairy","label":"Milk and dairy"}],
 "images":[{"key":"dairy/milk","label":"Milk","tier":"category","group":"dairy","category":"dairy/milk","url":"https://images.example.com/dairy/milk.jpg"},
  {"key":"dairy/milk-whole","label":"Whole milk","tier":"variant","group":"dairy","category":"dairy/milk","parent":"dairy/milk","url":"https://images.example.com/dairy/milk-whole.jpg"},
  {"key":"dairy/milk-oat","label":"Oat milk","tier":"something_new","group":"dairy","category":"dairy/milk","url":"https://images.example.com/dairy/milk-oat.jpg"}]}}`,
    );
  const set = await client().images();
  assert.equal(requests[0]!.url, '/v2/images');
  assert.equal(requests[0]!.headers['authorization'], 'Bearer test-key');
  assert.equal(set.version, 1);
  assert.equal(set.updated, '2026-11-17');
  assert.equal(set.fallback, 'generic/plate');
  assert.deepEqual(set.groups, [{ key: 'dairy', label: 'Milk and dairy' }]);
  assert.equal(set.images.length, 3);

  const milk = set.image('dairy/milk')!;
  assert.equal(milk.tier, ImageTier.category);
  assert.equal(milk.parent, null);
  assert.equal(milk.url, 'https://images.example.com/dairy/milk.jpg');

  assert.deepEqual(set.image('dairy/milk-whole'), {
    key: 'dairy/milk-whole',
    label: 'Whole milk',
    tier: ImageTier.variant,
    group: 'dairy',
    category: 'dairy/milk',
    parent: 'dairy/milk',
    url: 'https://images.example.com/dairy/milk-whole.jpg',
  });
  assert.equal(set.image('dairy/milk-oat')!.tier, ImageTier.unknown, 'tiers newer than the SDK still parse');
  assert.equal(set.image('dairy/yak-butter'), null);
});

test('an empty image set has empty lists', async () => {
  handler = (_, res) => reply(res, 200, '{"data":{"version":1,"groups":null}}');
  const set = await client().images();
  assert.deepEqual(set.groups, []);
  assert.deepEqual(set.images, []);
});

test('barcode links are escaped into the path', async () => {
  handler = (_, res) => reply(res, 200, `{"data":${foodJson}}`);
  await client().foodByBarcode(' https://id.gs1.org/01/03017624010701 ');
  assert.equal(requests[0]!.url, '/v2/foods/barcode/https:%2F%2Fid.gs1.org%2F01%2F03017624010701');
  await client().foodByBarcode('(01)03017624010701');
  assert.equal(requests[1]!.url, '/v2/foods/barcode/(01)03017624010701');
});

test('nutrient stats and the nutrient list parse', async () => {
  handler = (req, res) => {
    if (req.url === '/v2/foods/abc/nutrient-stats') {
      return reply(
        res,
        200,
        '{"data":{"id":"abc","per":"100 g","nutrients":{"protein":{"data_points":12,"min":3.12,"derivation":"A","derivation_description":"Analytical"}}}}',
      );
    }
    assert.equal(req.url, '/v2/nutrients');
    reply(
      res,
      200,
      '{"data":{"nutrients":[{"key":"calories","name":"Energy","unit":"kcal","group":"energy","core":true}],"other":[{"key":"usda_1018","name":"Ash","unit":"g","source":"USDA"}]}}',
    );
  };
  const c = client();
  const stats = await c.nutrientStats('abc');
  assert.equal(stats.foodId, 'abc');
  assert.equal(stats.per, '100 g');
  assert.deepEqual(stats.nutrients['protein'], {
    dataPoints: 12,
    stdError: null,
    min: 3.12,
    max: null,
    median: null,
    derivation: 'A',
    derivationDescription: 'Analytical',
    derivationBasis: null,
    footnote: null,
    updated: null,
  });
  const list = await c.nutrients();
  assert.deepEqual(list.nutrients, [{ key: 'calories', name: 'Energy', unit: 'kcal', group: 'energy', core: true }]);
  assert.deepEqual(list.other, [{ key: 'usda_1018', name: 'Ash', unit: 'g', source: 'USDA' }]);
});

describe('errors', () => {
  test('error statuses become typed errors carrying the API message', async () => {
    const expected: [number, new (...args: never[]) => FoodApiHttpError][] = [
      [400, FoodApiBadRequest],
      [401, FoodApiUnauthorized],
      [403, FoodApiForbidden],
      [404, FoodApiNotFound],
      [429, FoodApiRateLimited],
      [503, FoodApiUnavailable],
      [500, FoodApiServerError],
      [502, FoodApiServerError],
    ];
    for (const [status, type] of expected) {
      handler = (_, res) => reply(res, status, '{"message":"explained","data":{}}');
      await assert.rejects(client({ maxRetries: 0 }).food('x'), (e: unknown) => {
        assert.ok(e instanceof type, `${status}: ${String(e)}`);
        assert.ok(e instanceof FoodApiError);
        assert.equal(e.statusCode, status);
        assert.equal(e.message, 'explained');
        assert.equal(e instanceof FoodApiNotFound, status === 404);
        return true;
      });
    }
  });

  test('an answer that is not JSON keeps the status text', async () => {
    handler = (_, res) => {
      res.writeHead(500, 'Internal Server Error');
      res.end('<html>oops</html>');
    };
    await assert.rejects(client({ maxRetries: 0 }).food('x'), (e: unknown) => {
      assert.ok(e instanceof FoodApiServerError);
      assert.equal(e.message, 'Internal Server Error');
      return true;
    });
    handler = (_, res) => reply(res, 200, 'not json');
    await assert.rejects(client({ maxRetries: 0 }).food('x'), FoodApiServerError);
  });
});

describe('retries', () => {
  test('honour Retry-After in seconds', async () => {
    let calls = 0;
    handler = (_, res) =>
      ++calls === 1
        ? reply(res, 503, '{"message":"busy"}', { 'Retry-After': '1' })
        : reply(res, 200, `{"data":${foodJson}}`);
    const started = Date.now();
    assert.equal((await client().food('x')).name, 'Cola');
    const waited = Date.now() - started;
    assert.equal(calls, 2);
    assert.ok(waited >= 950 && waited < 3000, `waited ${waited} ms for a 1 s Retry-After`);
  });

  test('honour Retry-After 0 and as an HTTP date', async () => {
    let calls = 0;
    handler = (_, res) =>
      ++calls === 1
        ? reply(res, 429, '{"message":"slow down"}', { 'Retry-After': '0' })
        : reply(res, 200, `{"data":${foodJson}}`);
    let started = Date.now();
    await client().food('x');
    assert.equal(calls, 2);
    assert.ok(Date.now() - started < 200, 'retried at once, not after a backoff of 250 ms or more');

    calls = 0;
    handler = (_, res) =>
      ++calls === 1
        ? reply(res, 503, '{}', { 'Retry-After': new Date(Date.now() + 2000).toUTCString() })
        : reply(res, 200, `{"data":${foodJson}}`);
    started = Date.now();
    await client().food('x');
    const waited = Date.now() - started;
    assert.equal(calls, 2);
    assert.ok(waited >= 900 && waited < 3000, `waited ${waited} ms for a date about 2 s ahead`);
  });

  test('give up after maxRetries, backing off without Retry-After', async () => {
    handler = (_, res) => reply(res, 429, '{"message":"slow down"}');
    const started = Date.now();
    await assert.rejects(client().food('x'), FoodApiRateLimited);
    assert.equal(requests.length, 3);
    assert.ok(Date.now() - started >= 250 + 500, 'backed off 0.25-0.5 s, then 0.5-1 s');
  });

  test('502 and 504 are retried', async () => {
    for (const status of [502, 504]) {
      requests = [];
      handler = (_, res) => reply(res, status, '{}', { 'Retry-After': '0' });
      await assert.rejects(client({ maxRetries: 1 }).food('x'), FoodApiServerError);
      assert.equal(requests.length, 2, `${status}`);
    }
  });

  test('a long Retry-After is left to the caller', async () => {
    handler = (_, res) => reply(res, 503, '{"message":"busy"}', { 'Retry-After': '60' });
    await assert.rejects(client().food('x'), (e: unknown) => {
      assert.ok(e instanceof FoodApiUnavailable);
      assert.equal(e.retryAfter, 60_000);
      return true;
    });
    assert.equal(requests.length, 1);
  });

  test('not found and other client errors are not retried', async () => {
    for (const status of [400, 401, 403, 404, 500]) {
      requests = [];
      handler = (_, res) => reply(res, status, '{"message":"no"}');
      await assert.rejects(client().food('x'), FoodApiHttpError);
      assert.equal(requests.length, 1, `${status}`);
    }
  });

  test('network errors are retried, then reported', async () => {
    handler = (req) => req.socket.destroy();
    await assert.rejects(client({ maxRetries: 1 }).food('x'), FoodApiNetworkError);
    assert.equal(requests.length, 2);

    // Nothing listening
    const closed = createServer();
    await new Promise<void>((resolve) => closed.listen(0, '127.0.0.1', resolve));
    const port = (closed.address() as AddressInfo).port;
    await new Promise<void>((resolve) => closed.close(() => resolve()));
    await assert.rejects(client({ baseUrl: `http://127.0.0.1:${port}`, maxRetries: 0 }).food('x'), FoodApiNetworkError);
  });

  test('a slow attempt is aborted at the timeout, and retried', async () => {
    handler = () => {}; // Never answers
    await assert.rejects(client({ timeout: 100, maxRetries: 0 }).food('x'), FoodApiTimeoutError);
    assert.equal(requests.length, 1);

    requests = [];
    await assert.rejects(client({ timeout: 100, maxRetries: 1 }).food('x'), FoodApiTimeoutError);
    assert.equal(requests.length, 2);
  });
});

describe('cancellation', () => {
  test('aborting the signal aborts the request', async () => {
    handler = () => {}; // Never answers
    const controller = new AbortController();
    const call = client().search('apple', { signal: controller.signal });
    await waitFor(() => requests.length === 1);
    const closed = new Promise((resolve) => requests[0]!.socket.once('close', resolve));
    const started = Date.now();
    controller.abort();
    await assert.rejects(call, FoodApiCancelledError);
    assert.ok(Date.now() - started < 500);
    await closed; // The connection was dropped, not left waiting
  });

  test('a signal already aborted sends nothing', async () => {
    handler = (_, res) => reply(res, 200, `{"data":${foodJson}}`);
    await assert.rejects(client().food('x', { signal: AbortSignal.abort() }), FoodApiCancelledError);
    assert.equal(requests.length, 0);
  });

  test('aborting during a retry wait stops at once', async () => {
    handler = (_, res) => reply(res, 503, '{"message":"busy"}', { 'Retry-After': '5' });
    const controller = new AbortController();
    const call = client().food('x', { signal: controller.signal });
    await waitFor(() => requests.length === 1);
    await new Promise((resolve) => setTimeout(resolve, 50));
    const started = Date.now();
    controller.abort();
    await assert.rejects(call, FoodApiCancelledError);
    assert.ok(Date.now() - started < 500);
    assert.equal(requests.length, 1, 'no retry after the abort');
  });

  test('a signal that times out gives a timeout error', async () => {
    handler = () => {}; // Never answers
    await assert.rejects(client().food('x', { signal: AbortSignal.timeout(100) }), FoodApiTimeoutError);
    assert.equal(requests.length, 1, 'an overall deadline is not retried');
  });

  test('a session keeps only the latest search', async () => {
    handler = (req, res) => {
      const q = query(req).get('q');
      const answer = () =>
        reply(
          res,
          200,
          `{"data":[${foodJson}],"meta":{"query":"${q}","page":0,"limit":20,"total":1,"source":"catalog"}}`,
        );
      if (q === 'app')
        setTimeout(answer, 2000); // Slow, and superseded
      else answer();
    };
    const session = client().session();
    const first = session.search('app');
    const second = session.search('apple');
    await assert.rejects(first, FoodApiCancelledError);
    assert.equal((await second).query, 'apple');
  });

  test('searches and autocompletes cancel only their own kind', async () => {
    handler = (req, res) => {
      const body = req.url!.startsWith('/v2/foods/autocomplete')
        ? '{"data":[],"meta":{"query":"ap","limit":8,"total":0}}'
        : '{"data":[],"meta":{"query":"apple","page":0,"limit":20,"total":0,"source":"catalog"}}';
      setTimeout(() => reply(res, 200, body), 50);
    };
    const session = client().session();
    const search = session.search('apple');
    const suggest = session.autocomplete('ap');
    assert.equal((await search).query, 'apple');
    assert.equal((await suggest).query, 'ap');
  });

  test('a session cancels everything on close', async () => {
    handler = () => {}; // Never answers
    const session = client().session();
    const search = session.search('apple', { page: 1 });
    const suggest = session.autocomplete('app', { limit: 5 });
    await waitFor(() => requests.length === 2);
    session.cancel();
    await assert.rejects(search, FoodApiCancelledError);
    await assert.rejects(suggest, FoodApiCancelledError);
  });
});

test('invalid input sends nothing', async () => {
  handler = (_, res) => reply(res, 200, '{}');
  const c = client();
  const invalid: [string, () => Promise<unknown>][] = [
    ['empty query', () => c.search('  ')],
    ['long query', () => c.search('a'.repeat(201))],
    ['limit 51', () => c.search('apple', { limit: 51 })],
    ['limit 0', () => c.search('apple', { limit: 0 })],
    ['page -1', () => c.search('apple', { page: -1 })],
    ['page 1001', () => c.search('apple', { page: 1001 })],
    ['page 1.5', () => c.search('apple', { page: 1.5 })],
    ['autocomplete limit 21', () => c.autocomplete('app', { limit: 21 })],
    ['empty autocomplete', () => c.autocomplete('')],
    ['empty barcode', () => c.foodByBarcode(' ')],
    ['empty id', () => c.food('')],
    ['empty stats id', () => c.nutrientStats('')],
    ['bad client IP', () => c.food('x', { clientIp: '81.2.69' })],
  ];
  for (const [name, call] of invalid) {
    await assert.rejects(call(), FoodApiInvalidInput, name);
  }
  assert.equal(requests.length, 0);
});

test('query length counts characters, not UTF-16 units', async () => {
  handler = (_, res) => reply(res, 200, '{"data":[],"meta":{}}');
  await client().search('🍎'.repeat(200));
  assert.equal(requests.length, 1);
});

test('X-Client-IP carries the user address on calls that pass one', async () => {
  handler = (_, res) =>
    reply(
      res,
      200,
      '{"data":[],"meta":{"query":"cheddar","page":0,"limit":20,"total":0,"source":"catalog","region":"GB"}}',
    );
  const c = client();
  const page = await c.search('cheddar', { clientIp: ' 81.2.69.160 ' });
  assert.equal(page.region, 'GB');
  await c.search('cheddar');
  await c.autocomplete('ched', { clientIp: '2001:db8::1' });
  assert.deepEqual(
    requests.map((r) => r.headers['x-client-ip']),
    ['81.2.69.160', undefined, '2001:db8::1'],
  );

  const valid = [
    '192.0.2.1',
    '0.0.0.0',
    '::',
    '::1',
    '2001:db8::',
    'fe80::1%en0',
    '::ffff:192.0.2.1',
    '1:2:3:4:5:6:7:8',
  ];
  const invalid = [
    '192.0.2',
    '192.0.2.256',
    '192.0.02.1',
    '1:2:3:4:5:6:7:8:9',
    '1::2::3',
    'fe80::1%',
    'example.com',
    ':::',
  ];
  for (const ip of valid) await c.search('x', { clientIp: ip }).catch(() => assert.fail(`${ip} is valid`));
  for (const ip of invalid) await assert.rejects(c.food('x', { clientIp: ip }), FoodApiInvalidInput, ip);
});

test('accepts gzip', async () => {
  handler = (req, res) => {
    assert.match(String(req.headers['accept-encoding']), /gzip/);
    res.writeHead(200, { 'Content-Type': 'application/json', 'Content-Encoding': 'gzip' });
    res.end(gzipSync(`{"data":${foodJson}}`));
  };
  assert.equal((await client().food('x')).name, 'Cola');
});

test('one client reuses its connection', async () => {
  handler = (_, res) => reply(res, 200, `{"data":${foodJson}}`);
  const c = client();
  for (let i = 0; i < 6; i++) await c.food('x');
  // Node's fetch keeps a small pool (two connections here) and takes turns between them
  assert.ok(new Set(requests.map((r) => r.socket)).size <= 2, 'a new connection per request');
});

test('a base URL keeps its path, and a custom fetch is used', async () => {
  const seen: string[] = [];
  const c = new FoodApiClient({
    apiKey: 'test-key',
    baseUrl: 'https://api.example.com/food-proxy/',
    fetch: async (input, init) => {
      seen.push(input);
      assert.equal(new Headers(init.headers).get('authorization'), 'Bearer test-key');
      assert.ok(init.signal instanceof AbortSignal);
      return new Response(`{"data":${foodJson}}`, { status: 200, headers: { 'X-Cache': 'HIT' } });
    },
  });
  await c.food('01a163d2');
  assert.deepEqual(seen, ['https://api.example.com/food-proxy/v2/foods/01a163d2']);
});

async function waitFor(condition: () => boolean): Promise<void> {
  for (let i = 0; i < 200 && !condition(); i++) await new Promise((resolve) => setTimeout(resolve, 10));
  assert.ok(condition(), 'timed out waiting');
}

test('browsers get no User-Agent header; React Native does', async () => {
  const sent: (string | null)[] = [];
  const c = new FoodApiClient({
    apiKey: 'test-key',
    fetch: async (_, init) => {
      sent.push(new Headers(init.headers).get('user-agent'));
      return new Response(`{"data":${foodJson}}`);
    },
  });
  const g = globalThis as { document?: unknown };
  const navigator = Object.getOwnPropertyDescriptor(globalThis, 'navigator');
  g.document = {};
  try {
    await c.food('x');
    Object.defineProperty(globalThis, 'navigator', { value: { product: 'ReactNative' }, configurable: true });
    await c.food('x');
  } finally {
    delete g.document;
    if (navigator) Object.defineProperty(globalThis, 'navigator', navigator);
  }
  assert.deepEqual(sent, [null, `studio93-food-api-ts/${sdkVersion}`]);
});
