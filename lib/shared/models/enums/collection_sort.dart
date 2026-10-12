/// 当前用户收藏列表的排序方式，与服务端 sort 参数一致。
enum CollectionSort {
  defaultSort('default'),
  watch('watch');

  const CollectionSort(this.apiValue);

  final String apiValue;
}
