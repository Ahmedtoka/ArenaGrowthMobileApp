class Routes {
  Routes._();

  static const String login = '/login';
  static const String home = '/';

  static String chat(int groupId) => '/chat/$groupId';
  static String task(int taskId) => '/tasks/$taskId';
}
