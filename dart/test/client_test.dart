import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:studio93_food_api/studio93_food_api.dart';

const foodJson =
    '''{"id":"01a163d2-bfdc-7912-878d-4020b11915ab","name":"Cola","brand":null,"type":"generic","barcodes":[],
 "servings":[{"description":"100 g","measurement":"g","metric_amount":100,"metric_unit":"g","units":100,
   "nutrients":{"calories":37,"protein":0,"sugar":0.5,"fiber":null,"cnf_409":0.01}},
  {"description":"1 fl oz","measurement":"fl oz","metric_amount":29.57,"metric_unit":"ml","units":1,"generic":true,
   "nutrients":{"calories":10.94}}],
 "source":{"provider":"CNF","id":"2920"},"ingredients":null,"category":"Beverages",
 "attributes":{"alternate_names":"pop, soda, soft drink"},"nutrient_flags":{"sugar":"upper_bound","fat":"something_new"}}''';

/// A client that answers with [handler] and honours abort triggers like the platform clients do.
class FakeClient extends http.BaseClient {
  FakeClient(this.handler);

  final Future<http.Response> Function(http.BaseRequest request) handler;
  final requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final trigger = request is http.Abortable ? request.abortTrigger : null;
    final response = await Future.any([
      handler(request),
      if (trigger != null) trigger.then<http.Response>((_) => throw http.RequestAbortedException(request.url)),
    ]);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

http.Response json(int status, String body, {Map<String, String> headers = const {}}) =>
    http.Response.bytes(utf8.encode(body), status, headers: {'content-type': 'application/json', ...headers});

FoodApiClient clientWith(FakeClient fake, {Duration timeout = const Duration(seconds: 5), int maxRetries = 2}) =>
    FoodApiClient(
      apiKey: 'test-key',
      httpClient: fake,
      timeout: timeout,
      maxRetries: maxRetries,
      userAgent: 'my-app/1.0',
    );

void main() {
  test('search reports the country that ranked first', () async {
    final fake = FakeClient(
      (r) async => json(
        200,
        '{"data":[],"meta":{"query":"cheddar","page":0,"limit":20,"total":0,"source":"catalog","region":"CA"}}',
      ),
    );
    expect((await clientWith(fake).search('cheddar')).region, 'CA');
  });

  test('search sends the query and key and parses the page', () async {
    final fake = FakeClient(
      (r) async => json(
        200,
        '{"data":[$foodJson],"meta":{"query":"cola zero","page":2,"limit":5,"total":11,"source":"catalog"}}',
        headers: {'x-cache': 'HIT'},
      ),
    );
    final page = await clientWith(fake).search('Cola  Zero', page: 2, limit: 5);

    final req = fake.requests.single;
    expect(req.url.path, '/v2/foods/search');
    expect(req.url.queryParameters, {'q': 'Cola  Zero', 'page': '2', 'limit': '5'});
    expect(req.headers['Authorization'], 'Bearer test-key');
    expect(req.headers['User-Agent'], startsWith('my-app/1.0 studio93-food-api-dart/'));
    expect(page.query, 'cola zero');
    expect(page.total, 11);
    expect(page.cached, isTrue);
    expect(page.region, isNull, reason: 'no country ranked first');

    final food = page.foods.single;
    expect(food.servings.map((s) => s.generic), [false, true]);
    final n = food.servings.first.nutrients;
    expect(n.calories, 37);
    expect(n.fiber, isNull, reason: 'unknown values are null');
    expect(n['cnf_409'], 0.01);
    expect(food.flag('sugar'), NutrientFlag.upperBound);
    expect(food.flag('fat'), NutrientFlag.unknown, reason: 'flags newer than the SDK still parse');
    expect(food.flag('protein'), isNull);
    expect(food.alternateNames, ['pop', 'soda', 'soft drink']);
    expect(food.type, FoodType.generic);
    expect(food.image, isNull, reason: 'answers from before images still parse');
  });

  test('foods carry their image', () async {
    String withImage(String image) => foodJson.replaceFirst('"nutrient_flags"', '"image":$image,"nutrient_flags"');
    final fake = FakeClient(
      (r) async => json(200, switch (r.url.path) {
        '/v2/foods/cheddar' =>
          '{"data":${withImage('{"key":"dairy/cheddar","url":"https://images.example.com/dairy/cheddar.jpg","match":"food"}')}}',
        '/v2/foods/barcode/3017624010701' =>
          '{"data":${withImage('{"key":"generic/plate","url":"https://images.example.com/generic/plate.jpg","match":"fallback"}')}}',
        _ =>
          '{"data":${withImage('{"key":"dairy/cheese","url":"https://images.example.com/dairy/cheese.jpg","match":"something_new"}')}}',
      }),
    );
    final client = clientWith(fake);

    final image = (await client.food('cheddar')).image!;
    expect(image.key, 'dairy/cheddar');
    expect(image.url, 'https://images.example.com/dairy/cheddar.jpg');
    expect(image.match, ImageMatch.food);
    expect(image.isFallback, isFalse);

    expect((await client.foodByBarcode('3017624010701')).image!.isFallback, isTrue);

    final newer = (await client.food('gouda')).image!;
    expect(newer.match, ImageMatch.unknown, reason: 'matches newer than the SDK still parse');
    expect(newer.isFallback, isFalse);
  });

  test('the image set parses', () async {
    final fake = FakeClient(
      (r) async => json(
        200,
        '''{"data":{"version":1,"updated":"2026-11-17","fallback":"generic/plate",
 "groups":[{"key":"dairy","label":"Milk and dairy"}],
 "images":[{"key":"dairy/milk","label":"Milk","tier":"category","group":"dairy","category":"dairy/milk","url":"https://images.example.com/dairy/milk.jpg"},
  {"key":"dairy/milk-whole","label":"Whole milk","tier":"variant","group":"dairy","category":"dairy/milk","parent":"dairy/milk","url":"https://images.example.com/dairy/milk-whole.jpg"},
  {"key":"dairy/milk-oat","label":"Oat milk","tier":"something_new","group":"dairy","category":"dairy/milk","url":"https://images.example.com/dairy/milk-oat.jpg"}]}}''',
      ),
    );
    final set = await clientWith(fake).images();

    expect(fake.requests.single.url.path, '/v2/images');
    expect(fake.requests.single.headers['Authorization'], 'Bearer test-key');
    expect(set.version, 1);
    expect(set.updated, '2026-11-17');
    expect(set.fallback, 'generic/plate');
    expect(set.groups.single.label, 'Milk and dairy');
    expect(set.images, hasLength(3));

    final milk = set.image('dairy/milk')!;
    expect(milk.tier, ImageTier.category);
    expect(milk.parent, isNull);
    expect(milk.url, 'https://images.example.com/dairy/milk.jpg');

    final whole = set.image('dairy/milk-whole')!;
    expect(whole.tier, ImageTier.variant);
    expect(whole.label, 'Whole milk');
    expect(whole.group, 'dairy');
    expect(whole.category, 'dairy/milk');
    expect(whole.parent, 'dairy/milk');

    expect(set.image('dairy/milk-oat')!.tier, ImageTier.unknown, reason: 'tiers newer than the SDK still parse');
    expect(set.image('dairy/yak-butter'), isNull);
  });

  test('empty results are empty lists', () async {
    final fake = FakeClient((r) async => json(200, '{"data":null,"meta":{"total":0}}'));
    final client = clientWith(fake);
    expect((await client.search('xqzw')).foods, isEmpty);
    expect((await client.autocomplete('xq')).suggestions, isEmpty);
  });

  test('barcode links are escaped into the path', () async {
    final fake = FakeClient((r) async => json(200, '{"data":$foodJson}'));
    await clientWith(fake).foodByBarcode(' https://id.gs1.org/01/03017624010701 ');
    expect(
      fake.requests.single.url.toString(),
      endsWith('/v2/foods/barcode/https:%2F%2Fid.gs1.org%2F01%2F03017624010701'),
    );
  });

  test('error statuses become typed exceptions', () async {
    final expected = <int, TypeMatcher<FoodApiException>>{
      400: isA<FoodApiBadRequest>(),
      401: isA<FoodApiUnauthorized>(),
      404: isA<FoodApiNotFound>(),
      429: isA<FoodApiRateLimited>(),
      503: isA<FoodApiUnavailable>(),
      500: isA<FoodApiServerError>(),
    };
    for (final MapEntry(key: status, value: matcher) in expected.entries) {
      final fake = FakeClient((r) async => json(status, '{"message":"explained","data":{}}'));
      await expectLater(
        clientWith(fake, maxRetries: 0).food('x'),
        throwsA(matcher.having((e) => e.message, 'message', 'explained')),
      );
    }
  });

  test('retries honour Retry-After', () async {
    var calls = 0;
    final fake = FakeClient(
      (r) async => ++calls == 1
          ? json(503, '{"message":"busy"}', headers: {'retry-after': '0'})
          : json(200, '{"data":$foodJson}'),
    );
    final food = await clientWith(fake).food('x');
    expect(food.name, 'Cola');
    expect(calls, 2);
  });

  test('a long Retry-After is left to the caller', () async {
    final fake = FakeClient((r) async => json(503, '{"message":"busy"}', headers: {'retry-after': '60'}));
    await expectLater(
      clientWith(fake).food('x'),
      throwsA(isA<FoodApiUnavailable>().having((e) => e.retryAfter, 'retryAfter', const Duration(seconds: 60))),
    );
    expect(fake.requests, hasLength(1));
  });

  test('not found and other client errors are not retried', () async {
    final fake = FakeClient((r) async => json(404, '{"message":"food not found"}'));
    await expectLater(clientWith(fake).food('x'), throwsA(isA<FoodApiNotFound>()));
    expect(fake.requests, hasLength(1));
  });

  test('network errors are retried, then reported', () async {
    final fake = FakeClient((r) async => throw http.ClientException('connection reset', r.url));
    await expectLater(clientWith(fake, maxRetries: 1).food('x'), throwsA(isA<FoodApiNetworkException>()));
    expect(fake.requests, hasLength(2));
  });

  test('a slow attempt is aborted at the timeout', () async {
    final fake = FakeClient((r) => Completer<http.Response>().future); // Never answers
    await expectLater(
      clientWith(fake, timeout: const Duration(milliseconds: 50), maxRetries: 0).food('x'),
      throwsA(isA<FoodApiTimeoutException>()),
    );
  });

  test('a session keeps only the latest search', () async {
    final fake = FakeClient((r) async {
      final q = r.url.queryParameters['q'];
      if (q == 'app') await Future<void>.delayed(const Duration(seconds: 5)); // Slow, and superseded
      return json(200, '{"data":[$foodJson],"meta":{"query":"$q","page":0,"limit":20,"total":1,"source":"catalog"}}');
    });
    final session = clientWith(fake).session();
    final first = session.search('app');
    final second = session.search('apple');
    await expectLater(first, throwsA(isA<FoodApiCancelledException>()));
    expect((await second).query, 'apple');
  });

  test('a session cancels everything on close', () async {
    final fake = FakeClient((r) => Completer<http.Response>().future);
    final session = clientWith(fake).session();
    final search = session.search('apple');
    final suggest = session.autocomplete('app');
    session.cancel();
    await expectLater(search, throwsA(isA<FoodApiCancelledException>()));
    await expectLater(suggest, throwsA(isA<FoodApiCancelledException>()));
  });

  test('invalid input sends nothing', () async {
    final fake = FakeClient((r) async => json(200, '{}'));
    final client = clientWith(fake);
    expect(() => client.search('  '), throwsA(isA<FoodApiInvalidInput>()));
    expect(() => client.search('a' * 201), throwsA(isA<FoodApiInvalidInput>()));
    expect(() => client.search('apple', limit: 51), throwsA(isA<FoodApiInvalidInput>()));
    expect(() => client.autocomplete('app', limit: 21), throwsA(isA<FoodApiInvalidInput>()));
    expect(() => client.foodByBarcode(''), throwsA(isA<FoodApiInvalidInput>()));
    expect(fake.requests, isEmpty);
  });

  test('nutrient stats and the nutrient list parse', () async {
    final fake = FakeClient(
      (r) async => switch (r.url.path) {
        '/v2/foods/abc/nutrient-stats' => json(
          200,
          '{"data":{"id":"abc","per":"100 g","nutrients":{"protein":{"data_points":12,"min":3.12,"derivation":"A","derivation_description":"Analytical"}}}}',
        ),
        _ => json(
          200,
          '{"data":{"nutrients":[{"key":"calories","name":"Energy","unit":"kcal","group":"energy","core":true}],"other":[{"key":"usda_1018","name":"Ash","unit":"g","source":"USDA"}]}}',
        ),
      },
    );
    final client = clientWith(fake);
    final stats = await client.nutrientStats('abc');
    expect(stats.nutrients['protein']!.dataPoints, 12);
    expect(stats.nutrients['protein']!.derivationDescription, 'Analytical');
    final list = await client.nutrients();
    expect(list.nutrients.single.core, isTrue);
    expect(list.other.single.key, 'usda_1018');
  });
}
