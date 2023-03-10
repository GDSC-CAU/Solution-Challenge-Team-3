import 'package:app/models/food_menu.dart';
import 'package:app/models/model_factory.dart';

class FoodMap implements Model<FoodMap> {
  String category = "";
  final _foodMenuFactory = ModelFactory(FoodMenu());
  List<FoodMenu> menu = [];

  @override
  void set(jsonMap) {
    category = jsonMap["category"] as String;
    _foodMenuFactory.serializeList(jsonMap["menu"] as List<JsonMap>);
    menu = _foodMenuFactory.dataList;
  }

  @override
  JsonMap toJson() => {
        "category": category,
        "menu": menu.map((menu) => menu.toJson()),
      };

  @override
  FoodMap create() => FoodMap();

  @override
  String toString() =>
      "\n{ \n  category: $category, \n  menu: ${menu.toString()}\n }\n";
}
