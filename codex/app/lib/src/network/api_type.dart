enum ApiType {
  example(domain: 'jsonplaceholder.typicode.com', basePath: '');

  const ApiType({required this.domain, required this.basePath});

  final String domain;
  final String basePath;

  String get baseUrl => 'https://$domain$basePath';
}
