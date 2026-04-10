import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';
import 'package:super_overlay/features/login/data/login_models.dart';

part 'login_api.g.dart';

@RestApi()
abstract class LoginApi {
  factory LoginApi(Dio dio, {String? baseUrl}) = _LoginApi;

  @POST('/auth/login')
  Future<LoginResponse> login(@Body() Map<String, dynamic> request);
}
