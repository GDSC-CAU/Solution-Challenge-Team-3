// ignore_for_file: constant_identifier_names, non_constant_identifier_names

import 'package:app/core/block/block.dart';
import 'package:app/core/block/menu_block.dart';
import 'package:app/core/clusters/clustering_engine.dart';
import 'package:app/core/menu_block_parser.dart';
import 'package:app/core/utils/math.dart';
import 'package:app/core/utils/sort.dart';
import 'package:app/core/utils/statics.dart';
import 'package:app/models/food_menu.dart';
import 'package:app/models/model_factory.dart';
import 'package:app/utils/array.dart';
import 'package:app/utils/text.dart';

typedef MenuBlockList = List<MenuBlock>;

class MenuEngine {
  final ClusteringEngine clusteringEngine;
  final MenuBlockParser menuBlockParser = MenuBlockParser();

  MenuBlockList menuBlockList = [];
  MenuBlockList _unMatchedNameBlockList = [];
  MenuBlockList _unMatchedPriceBlockList = [];

  List<FoodMenu> _foodMenu = [];
  List<FoodMenu> get foodMenu {
    _matchAllFoodMenu();
    return _foodMenu;
  }

  MenuEngine()
      : clusteringEngine = ClusteringEngine(
          menuBlockList: [],
          maximumAngleOfYAxis: 5,
          maximumPointGapRatio: 4,
          minimumPointOfLine: 2,
        );

  void _clearPreviousResult() {
    clusteringEngine.clearClusteredResult();

    menuBlockList = [];
    _foodMenu = [];
    _unMatchedNameBlockList = [];
    _unMatchedPriceBlockList = [];
  }

  /// Parse food menu
  Future<void> parse(
    String imagePath,
  ) async {
    _clearPreviousResult();

    await menuBlockParser.parse(
      imagePath,
    );
    menuBlockList = menuBlockParser.menuBlockList;

    _setupBlockList();
    clusteringEngine.updateMenuBlockList(
      menuBlockList,
    );
  }

  void _setupBlockList() {
    _sortBlockListByCoordYX();
    _normalizeBlockList();
    _filterBlockByHeightDistribution();
    _sortBlockListByCoordYX();
    _combineBlockList(
      scaleRatioOfSearchWidth: 3,
      scaleRatioOfSearchHeight: 0.65,
    );
    _filterBlocksByKOREAN_JOSA_LIST();
    _removeInvalidCharacters();
  }

  // ignore: use_setters_to_change_properties
  void _updateMenuBlockList(MenuBlockList updatedMenuBlockList) {
    menuBlockList = updatedMenuBlockList;
  }

  /// sort coord by `y` -> `x`
  void _sortBlockListByCoordYX() {
    menuBlockList.sort(
      (blockA, blockB) => ascendingSort(
        blockA.block.center.y,
        blockB.block.center.y,
      ),
    );

    final sortedMenuBlockList = menuBlockList.fold<MenuBlockList>(
      [],
      (sorted, block) {
        if (sorted.isEmpty ||
            block.block.center.y >= sorted.last.block.center.y) {
          sorted.add(block);
          return sorted;
        }

        final tempCenterCoord = sorted.last.block.center;
        final centerCoord = block.block.center;

        final centerCoordSortedByX = Coord(
          x: tempCenterCoord.x > centerCoord.x
              ? centerCoord.x
              : tempCenterCoord.x,
          y: centerCoord.y,
        );

        final width = block.block.width;
        final height = block.block.height;

        sorted.add(
          MenuBlock(
            text: block.text,
            block: Block(
              initialPosition: RectPosition.fromBox(
                centerCoordSortedByX,
                width: width,
                height: height,
              ),
            ),
          ),
        );
        return sorted;
      },
    );

    _updateMenuBlockList(sortedMenuBlockList);
  }

  void _normalizeBlockList() {
    final yCoordList = menuBlockList.map((e) => e.block.tl.y).toList();
    final heightList = menuBlockList.map((e) => e.block.height).toList();

    final heightStd = Statics.std(heightList).toInt();
    final yCoordDiffList = heightList.fold<List<int>>([], (acc, curr) {
      if (acc.isEmpty) acc.add(curr);
      acc.add((curr - acc.last).abs());
      return acc;
    });
    final yCoordDiffStd = Statics.std(yCoordDiffList).toInt();

    final normalizedYCoordList = Statics.normalize(
      intList: yCoordList,
      interval: yCoordDiffStd,
    );
    final normalizedHeight = Statics.normalize(
      intList: heightList,
      interval: heightStd,
    );

    final normalizedMenuRectBlockList =
        normalizedYCoordList.folder<MenuBlockList>(
      [],
      (normalizedList, normalizedY, i, _) {
        final currentMenuBlock = menuBlockList[i];
        final currentRectHeight = normalizedHeight[i];

        final currentLeftX = currentMenuBlock.block.tl.x;
        final currentRightX = currentMenuBlock.block.tr.x;

        final updatedMenuBlock = MenuBlock(
          text: currentMenuBlock.text,
          block: Block(
            initialPosition: RectPosition(
              tl: Coord(x: currentLeftX, y: normalizedY),
              bl: Coord(x: currentLeftX, y: normalizedY + currentRectHeight),
              tr: Coord(x: currentRightX, y: normalizedY),
              br: Coord(x: currentRightX, y: normalizedY + currentRectHeight),
            ),
          ),
        );

        normalizedList.add(updatedMenuBlock);
        return normalizedList;
      },
    );

    _updateMenuBlockList(normalizedMenuRectBlockList);
  }

  void _combineBlockList({
    double scaleRatioOfSearchWidth = 2.5,
    double scaleRatioOfSearchHeight = 0.75,
  }) {
    final heightAvg = Statics.avg(
      menuBlockList.map((e) => e.block.height).toList(),
    );
    final toleranceX = (heightAvg * scaleRatioOfSearchWidth).toInt();
    final toleranceY = (heightAvg * scaleRatioOfSearchHeight).toInt();

    MenuBlockList combineBlockListUntilEnd(
      MenuBlockList combineTargetBlockList,
    ) {
      final Set<int> _mergedIndex = {};

      final mergedBlockList = combineTargetBlockList.folder<MenuBlockList>(
        [],
        (mergedBlocks, currentMenuBlock, currentI, tot) {
          if (_mergedIndex.contains(currentI)) {
            return mergedBlocks;
          }

          final combinedMenuBlock = tot.folder<MenuBlockList>(
            [currentMenuBlock],
            (combinedMenuBlock, iterBlock, iterI, _) {
              if (currentI == iterI) {
                return combinedMenuBlock;
              }
              if (_mergedIndex.contains(iterI)) {
                return combinedMenuBlock;
              }

              if (MenuBlock.getCombinableState(
                combinedMenuBlock.last,
                iterBlock,
                toleranceX: toleranceX,
                toleranceY: toleranceY,
              )) {
                final combinedBlock = MenuBlock.combine(
                  combinedMenuBlock.last,
                  iterBlock,
                );
                combinedMenuBlock.add(combinedBlock);

                _mergedIndex.add(iterI);

                return combinedMenuBlock;
              }

              return combinedMenuBlock;
            },
          ).last;

          mergedBlocks.add(combinedMenuBlock);
          return mergedBlocks;
        },
      );

      final checkedIndex = <int>{};

      final isCombineNotCompleted = mergedBlockList
          .mapper<bool>(
            (currBlock, currI, _) => mergedBlockList.mapper<bool>(
              (iterBlock, iterI, _) {
                if (iterI == currI) return false;
                if (checkedIndex.contains(iterI)) return false;

                final isCombinePossible = MenuBlock.getCombinableState(
                  currBlock,
                  iterBlock,
                  toleranceX: toleranceX,
                  toleranceY: toleranceY,
                );
                checkedIndex.add(iterI);
                return isCombinePossible;
              },
            ).any((isCombinePossible) => isCombinePossible),
          )
          .any((shouldCombineMore) => shouldCombineMore);

      if (isCombineNotCompleted) {
        return combineBlockListUntilEnd(mergedBlockList);
      } else {
        return mergedBlockList;
      }
    }

    final combinedBlockList = combineBlockListUntilEnd(menuBlockList);
    _updateMenuBlockList(combinedBlockList);
  }

  /// Filter tiny & huge text by rect height
  void _filterBlockByHeightDistribution() {
    final heightList = menuBlockList.map((e) => e.block.height).toList();

    bool _getFilterStateByStepPoints(
      int currentIndex, {
      required int? first,
      required int? last,
    }) {
      if (first == null) return false;
      if (last == null) return currentIndex <= first;
      return currentIndex <= first || currentIndex > last;
    }

    final stepPoints = Statics.getSideStepPoint(heightList);
    final filteredMenuBlockList = menuBlockList.folder<MenuBlockList>(
      [],
      (filtered, block, currentIndex, _) {
        if (_getFilterStateByStepPoints(
          currentIndex,
          first: stepPoints["first"],
          last: stepPoints["last"],
        )) return filtered;

        filtered.add(block);
        return filtered;
      },
    );

    _updateMenuBlockList(filteredMenuBlockList);
  }

  String _removeNonKoreanEnglishPriceNumber(String text) {
    const divider = "";
    final RegExp nonKoreanEnglishPriceNumber =
        RegExp(r'[^\uAC00-\uD7A3???-??????-??????-???a-zA-Z0-9,.&]');
    return text
        .replaceAll(
          nonKoreanEnglishPriceNumber,
          divider,
        )
        .trim();
  }

  String _removeLastComma(String text) =>
      text.endsWith(",") ? text.replaceAll(RegExp(','), "") : text;

  void _removeInvalidCharacters() {
    final removedNonKoreanEnglishNumber = menuBlockList
        .map(
          (e) => MenuBlock(
            text: _removeLastComma(
              _removeNonKoreanEnglishPriceNumber(e.text),
            ),
            block: e.block,
          ),
        )
        .toList();

    _updateMenuBlockList(removedNonKoreanEnglishNumber);
  }

  void _filterBlocksByKOREAN_JOSA_LIST() {
    const Set<String> KOREAN_JOSA_LIST = {
      "???",
      "???",
      "???",
      "???",
      "???",
      "???",
      "???",
      "???",
      "???",
      "???",
      "???",
      "???",
      "???",
      "???",
      "???",
      "???",
      "???",
      "???",
      "???",
      "???",
      "???",
      "???",
      "???",
      "???",
      "???",
      "??????",
      "??????",
      "??????",
      "??????",
      "??????",
      "??????",
      "??????",
      "??????",
      "??????",
      "??????",
      "??????",
      "??????",
      "??????",
      "??????",
      "??????",
      "??????",
      "??????",
      "??????",
      "??????",
      "??????",
      "??????",
      "??????",
      "??????",
      "??????",
      "??????",
      "??????",
      "??????",
    };

    const KOREAN_LIST_NUMBER = <String>{
      "??????",
      "???",
      "???",
    };

    const KOREAN_PERSONAL_PRONOUNS = <String>{
      "??????",
    };

    const KOREAN_FILTER = [
      ...KOREAN_JOSA_LIST,
      ...KOREAN_LIST_NUMBER,
      ...KOREAN_PERSONAL_PRONOUNS
    ];

    bool _isJOSAIncluded(String word) => KOREAN_FILTER
        .map((josa) => word.endsWith(josa))
        .any((isJosaIncluded) => isJosaIncluded);

    final filteredByJOSA = menuBlockList.filter(
      (block, i) {
        const indent = " ";
        final wordListByIndent = block.text
            .split(indent)
            .map((word) => _removeNonKoreanEnglishPriceNumber(word));

        const maximumCountOfJosa = 1;
        final isSentence = wordListByIndent
                .map((word) => _isJOSAIncluded(word))
                .toList()
                .filter((josa, _) => josa)
                .length >
            maximumCountOfJosa;

        if (isSentence) {
          print("?????? ?????????: ${block.text}");
          return false;
        }
        return true;
      },
    );

    _updateMenuBlockList(filteredByJOSA);
  }

  MenuBlockList _filterBlockList({
    required MenuBlockList baseBlockList,
    required MenuBlockList removeTargetBlockList,
  }) =>
      baseBlockList.filter(
        (baseBlock, i) =>
            removeTargetBlockList.any(
              (removeTargetBlock) => MenuBlock.isSameMenuBlock(
                removeTargetBlock,
                baseBlock,
              ),
            ) ==
            false,
      );

  MenuBlockList _searchBlocksInYAxis({
    required MenuBlockList searchTargetBlockList,
    required MenuBlock standardBlock,
    required int searchYHeight,
  }) {
    final MenuBlockList searchedList =
        searchTargetBlockList.folder<MenuBlockList>(
      [],
      (ySimilarBlockList, targetBlock, index, _) {
        final isBlockInRange =
            (standardBlock.block.tl.y - targetBlock.block.tl.y).abs() <=
                searchYHeight;
        if (isBlockInRange) {
          ySimilarBlockList.add(targetBlock);
        }
        return ySimilarBlockList;
      },
    );

    return searchedList;
  }

  FoodMenu _createFoodMenu({
    required String name,
    required String price,
  }) {
    final foodMenu = ModelFactory(FoodMenu());
    foodMenu.serialize({
      "name": name,
      "price": price,
    });

    return foodMenu.data!;
  }

  List<LineAlignCluster> _getLineAlignmentClusteredBlockList({
    required List<MenuBlock> clusterTargetMenuBlock,
  }) {
    clusteringEngine.lineAlignmentClustering(
      clusterTargetMenuBlock: clusterTargetMenuBlock,
    );
    final clusteredList = clusteringEngine.lineAlignmentClusters;
    clusteredList.sort(
      (a, b) => ascendingSort(
        a.middlePoint.x,
        b.middlePoint.x,
      ),
    );

    clusteringEngine.clearClusteredResult();

    return clusteredList;
  }

  void _matchFoodMenuByAlignmentClustering() {
    final nameBlockList = menuBlockList.filter(
      (block, _) => isPriceText(block.text) == false,
    );
    final nameBlockClusterList = _getLineAlignmentClusteredBlockList(
      clusterTargetMenuBlock: nameBlockList,
    );

    final priceBlockList = menuBlockList.filter(
      (block, _) => isPriceText(block.text),
    );
    final priceAlignClusterList = _getLineAlignmentClusteredBlockList(
      clusterTargetMenuBlock: priceBlockList,
    );

    List<num> _getLineClusterGapList(
      List<LineAlignCluster> lineAlignmentClusterList,
    ) {
      return lineAlignmentClusterList.folder<List<num>>(
        [],
        (gapList, cluster, i, tot) {
          if (i == 0) return gapList;
          final prev = tot[i - 1];
          final gapBetweenLine =
              (cluster.middlePoint.x - prev.middlePoint.x).abs();

          final isSameLine = gapBetweenLine <= clusteringEngine.blockWidthAvg;
          if (isSameLine) {
            return gapList;
          }

          gapList.add(gapBetweenLine);
          return gapList;
        },
      );
    }

    final List<num> lineClusterGapList = [];
    lineClusterGapList.addAll(_getLineClusterGapList(nameBlockClusterList));
    lineClusterGapList.addAll(_getLineClusterGapList(priceAlignClusterList));

    final lineClusterGapAvg = Statics.avg(lineClusterGapList);

    final MenuBlockList matchedPriceList = [];
    final MenuBlockList matchedNameList = [];

    final menuList = nameBlockClusterList.folder<List<FoodMenu>>(
      [],
      (foodMenuList, nameCluster, targetI, tot) {
        final targetPriceClusterList = priceAlignClusterList.filter(
          (priceCluster, i) {
            final gapXWithNameCluster =
                priceCluster.middlePoint.x - nameCluster.middlePoint.x;
            return gapXWithNameCluster > 0 &&
                gapXWithNameCluster < lineClusterGapAvg;
          },
        );

        final matchedFoodMenuList =
            nameCluster.clusteredMenuBlockList.folder<List<FoodMenu>>(
          [],
          (matchedFoodMenuList, nameBlock, i, tot) {
            final targetPriceBlockList = targetPriceClusterList
                .map((priceCluster) => priceCluster.clusteredMenuBlockList)
                .toList()
                .flat<MenuBlock>();

            final combinableBlockList = targetPriceBlockList
                .where(
                  (element) => MenuBlock.getCombinableState(
                    nameBlock,
                    element,
                    toleranceX: lineClusterGapAvg.toInt(),
                    toleranceY: clusteringEngine.blockHeightAvg.toInt(),
                    skipPrice: false,
                  ),
                )
                .toList();

            /// no matched price block found
            if (combinableBlockList.isEmpty) {
              return matchedFoodMenuList;
            }

            final combineTargetBlockList = combinableBlockList.filter(
              (priceBlock, i) =>
                  matchedPriceList.any(
                    (matchedPriceBlock) => MenuBlock.isSameMenuBlock(
                      priceBlock,
                      matchedPriceBlock,
                    ),
                  ) ==
                  false,
            );

            /// no matched price block found
            if (combineTargetBlockList.isEmpty) {
              return matchedFoodMenuList;
            }

            /// combinable price block count, over 2
            /// TODO: price block ????????? ?????? block ?????? -> ?????? ????????? ?????? block??? ???????????? ??????????????? ???, ?????? ????????? ?????????????????? ????????????
            if (combineTargetBlockList.length > 1) {
              final closestBlockIndex = Math.findMinIndex(
                combineTargetBlockList
                    .map(
                      (e) => e.block.center.distanceTo(
                        nameBlock.block.center,
                      ),
                    )
                    .toList(),
              );
              final closestPriceBlock = combinableBlockList[closestBlockIndex];
              matchedFoodMenuList.add(
                _createFoodMenu(
                  name: nameBlock.text,
                  price: closestPriceBlock.text,
                ),
              );
              matchedNameList.add(nameBlock);
              matchedPriceList.add(closestPriceBlock);
              return matchedFoodMenuList;
            }

            /// only price block
            matchedFoodMenuList.add(
              _createFoodMenu(
                name: nameBlock.text,
                price: combineTargetBlockList.first.text,
              ),
            );
            matchedNameList.add(nameBlock);
            matchedPriceList.add(combineTargetBlockList.first);

            return matchedFoodMenuList;
          },
        ).toList();
        foodMenuList.addAll(matchedFoodMenuList);

        return foodMenuList;
      },
    );

    final unMatchedPriceBlockList = _filterBlockList(
      baseBlockList: priceBlockList,
      removeTargetBlockList: matchedPriceList,
    );
    final unMatchedNameBlockList = _filterBlockList(
      baseBlockList: nameBlockList,
      removeTargetBlockList: matchedNameList,
    );
    _unMatchedPriceBlockList.addAll(unMatchedPriceBlockList);
    _unMatchedNameBlockList.addAll(unMatchedNameBlockList);

    _foodMenu.addAll(menuList);
  }

  void _matchUnMatchedNameAndPrice() {
    final MenuBlockList matchedNameBlockList = [];
    final MenuBlockList matchedPriceBlockList = [];

    final menuList = _unMatchedNameBlockList.fold<List<FoodMenu>>(
      [],
      (accMenuList, nameBlock) {
        final searchedPriceBlockList = _searchBlocksInYAxis(
          standardBlock: nameBlock,
          searchTargetBlockList: _unMatchedPriceBlockList,
          searchYHeight: clusteringEngine.blockHeightAvg.toInt(),
        );
        searchedPriceBlockList.sort(
          (a, b) => ascendingSort(a.block.center.x, b.block.center.x),
        );

        final priceBlockListOfRightSideOfCurrentNameBlock =
            searchedPriceBlockList.filter(
          (element, i) => element.block.center.x > nameBlock.block.center.x,
        );

        if (priceBlockListOfRightSideOfCurrentNameBlock.isEmpty) {
          return accMenuList;
        }

        final combineTargetPriceBlockList =
            priceBlockListOfRightSideOfCurrentNameBlock.filter(
          (priceBlock, i) =>
              matchedPriceBlockList.any(
                (combinedPriceBlock) => MenuBlock.isSameMenuBlock(
                  priceBlock,
                  combinedPriceBlock,
                ),
              ) ==
              false,
        );
        if (combineTargetPriceBlockList.isEmpty) {
          return accMenuList;
        }
        if (combineTargetPriceBlockList.length > 1) {
          final closestBlockIndex = Math.findMinIndex(
            combineTargetPriceBlockList
                .map(
                  (e) => e.block.center.distanceTo(
                    nameBlock.block.center,
                  ),
                )
                .toList(),
          );
          final closestPriceBlock =
              combineTargetPriceBlockList[closestBlockIndex];

          matchedNameBlockList.add(nameBlock);
          matchedPriceBlockList.add(closestPriceBlock);

          final foodMenu = _createFoodMenu(
            name: nameBlock.text,
            price: closestPriceBlock.text,
          );
          accMenuList.add(foodMenu);
          return accMenuList;
        }

        final closestPriceBlock =
            priceBlockListOfRightSideOfCurrentNameBlock.first;

        final foodMenu = _createFoodMenu(
          name: nameBlock.text,
          price: closestPriceBlock.text,
        );
        matchedNameBlockList.add(nameBlock);
        matchedPriceBlockList.add(closestPriceBlock);

        accMenuList.add(foodMenu);
        return accMenuList;
      },
    );

    _unMatchedNameBlockList = _filterBlockList(
      baseBlockList: _unMatchedNameBlockList,
      removeTargetBlockList: matchedNameBlockList,
    );
    _unMatchedPriceBlockList = _filterBlockList(
      baseBlockList: _unMatchedPriceBlockList,
      removeTargetBlockList: matchedPriceBlockList,
    );

    _foodMenu.addAll(menuList);
  }

  /// Match `name` to `price`
  ///
  /// 1. `LineAlignment` clustering
  /// 2. Use `name` to `price` matching algorithm
  void _matchAllFoodMenu() {
    _matchFoodMenuByAlignmentClustering();
    _matchUnMatchedNameAndPrice();
  }
}
