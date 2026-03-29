import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../api/api_client.dart';

class ClubSubscriptionScreen extends StatefulWidget {
  final int clubId;
  const ClubSubscriptionScreen({super.key, required this.clubId});

  @override
  State<ClubSubscriptionScreen> createState() => _ClubSubscriptionScreenState();
}

class _ClubSubscriptionScreenState extends State<ClubSubscriptionScreen> {
  static const _kStandardId = 'stagemate_standard_monthly';
  static const _kProId = 'stagemate_pro_monthly';

  Map<String, dynamic>? _subInfo;
  bool _isLoading = true;
  String? _error;

  List<ProductDetails> _products = [];
  late StreamSubscription<List<PurchaseDetails>> _purchaseSub;
  bool _purchasing = false;

  @override
  void initState() {
    super.initState();
    _purchaseSub = InAppPurchase.instance.purchaseStream.listen(
      _onPurchaseUpdate,
      onError: (e) {
        if (mounted) setState(() => _error = e.toString());
      },
    );
    _load();
  }

  @override
  void dispose() {
    _purchaseSub.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    Map<String, dynamic>? loadedSub;
    try {
      final sub = await ApiClient.getClubSubscription(widget.clubId);
      final available = await InAppPurchase.instance.isAvailable();
      if (available) {
        final resp = await InAppPurchase.instance
            .queryProductDetails({_kStandardId, _kProId});
        if (mounted) setState(() => _products = resp.productDetails);
      }
      loadedSub = sub;
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() {
        _subInfo = loadedSub;
        _isLoading = false;
      });
    }
  }

  Future<void> _purchase(String productId) async {
    final product = _products.firstWhere(
      (p) => p.id == productId,
      orElse: () => throw Exception('상품을 찾을 수 없습니다.'),
    );
    setState(() => _purchasing = true);
    try {
      final param = PurchaseParam(productDetails: product);
      await InAppPurchase.instance.buyNonConsumable(purchaseParam: param);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
        );
        setState(() => _purchasing = false);
      }
    }
  }

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      bool completed = false;
      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        try {
          final platform = defaultTargetPlatform == TargetPlatform.iOS
              ? 'apple'
              : 'google';
          await ApiClient.verifyClubSubscription(
            widget.clubId,
            productId: purchase.productID,
            transactionId: purchase.purchaseID ?? '',
            platform: platform,
            receiptData: purchase.verificationData.serverVerificationData,
          );
          await InAppPurchase.instance.completePurchase(purchase);
          completed = true;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('구독이 활성화됐습니다! 🎉'),
                backgroundColor: Colors.green,
              ),
            );
            await _load();
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('구독 확인 실패: ${e.toString().replaceFirst("Exception: ", "")}'), backgroundColor: Colors.red),
            );
          }
        }
      } else if (purchase.status == PurchaseStatus.error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('구매 오류: ${purchase.error?.message ?? "알 수 없는 오류"}'), backgroundColor: Colors.red),
          );
        }
      }
      if (!completed && purchase.pendingCompletePurchase) {
        await InAppPurchase.instance.completePurchase(purchase);
      }
    }
    if (mounted) setState(() => _purchasing = false);
  }

  String _planLabel(String plan) {
    switch (plan) {
      case 'standard': return 'STANDARD';
      case 'pro': return 'PRO';
      default: return 'FREE';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('플랜 & 구독'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _load, child: const Text('다시 시도')),
                    ],
                  ),
                )
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    final sub = _subInfo!;
    final currentPlan = sub['plan'] as String? ?? 'free';
    final expiresAt = sub['plan_expires_at'] as String?;
    final usedMb = (sub['storage_used_mb'] as num?)?.toDouble() ?? 0;
    final quotaMb = (sub['storage_quota_mb'] as num?)?.toDouble() ?? 1024;
    final boostCredits = sub['boost_credits'] as int? ?? 0;

    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 현재 플랜 요약
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.workspace_premium),
                        const SizedBox(width: 8),
                        Text(
                          '현재 플랜: ${_planLabel(currentPlan)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    if (expiresAt != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '만료: $expiresAt',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onPrimaryContainer.withOpacity(0.7),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    // 스토리지 바
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('스토리지', style: TextStyle(fontSize: 13)),
                        Text(
                          '${usedMb.toStringAsFixed(0)}MB / ${(quotaMb / 1024).toStringAsFixed(0)}GB',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: quotaMb > 0 ? (usedMb / quotaMb).clamp(0, 1) : 0,
                        minHeight: 8,
                        backgroundColor: Theme.of(context).colorScheme.surface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.rocket_launch, size: 16),
                        const SizedBox(width: 6),
                        Text('홍보 크레딧: $boostCredits개', style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '플랜 선택',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            // 플랜 카드 3개
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _PlanCard(
                    name: 'FREE',
                    price: '무료',
                    storage: '1GB',
                    boostCredits: 0,
                    isCurrent: currentPlan == 'free',
                    isRecommended: false,
                    onTap: null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _PlanCard(
                    name: 'STANDARD',
                    price: '₩9,900/월',
                    storage: '50GB',
                    boostCredits: 5,
                    isCurrent: currentPlan == 'standard',
                    isRecommended: true,
                    onTap: (_purchasing || currentPlan == 'standard')
                        ? null
                        : () => _purchase(_kStandardId),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _PlanCard(
                    name: 'PRO',
                    price: '₩29,000/월',
                    storage: '200GB',
                    boostCredits: 20,
                    isCurrent: currentPlan == 'pro',
                    isRecommended: false,
                    onTap: (_purchasing || currentPlan == 'pro')
                        ? null
                        : () => _purchase(_kProId),
                  ),
                ),
              ],
            ),
            if (_purchasing) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 8),
              const Center(child: Text('결제 처리 중...', style: TextStyle(fontSize: 12))),
            ],
            const SizedBox(height: 24),
            Text(
              '* 구독은 App Store / Google Play를 통해 결제됩니다.\n'
              '* 구독은 다음 결제일 전에 취소하지 않으면 자동 갱신됩니다.',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final String name;
  final String price;
  final String storage;
  final int boostCredits;
  final bool isCurrent;
  final bool isRecommended;
  final VoidCallback? onTap;

  const _PlanCard({
    required this.name,
    required this.price,
    required this.storage,
    required this.boostCredits,
    required this.isCurrent,
    required this.isRecommended,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Card(
          elevation: isCurrent ? 4 : 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: isCurrent
                ? BorderSide(color: colorScheme.primary, width: 2)
                : BorderSide.none,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isCurrent ? colorScheme.primary : null,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    price,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                  const Divider(height: 16),
                  _Feature(icon: Icons.storage, label: storage),
                  const SizedBox(height: 4),
                  _Feature(
                    icon: Icons.rocket_launch,
                    label: boostCredits == 0 ? '없음' : '월 ${boostCredits}회',
                  ),
                  const SizedBox(height: 12),
                  if (isCurrent)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '현재 플랜',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    )
                  else if (onTap != null)
                    FilledButton(
                      onPressed: onTap,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        textStyle: const TextStyle(fontSize: 11),
                      ),
                      child: const Text('선택'),
                    )
                  else
                    const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ),
        if (isRecommended)
          Positioned(
            top: -8,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  '추천',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Feature extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Feature({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 12, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 11),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
