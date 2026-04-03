import 'package:flutter/material.dart';

class OnboardingStep {
  final String menuKey;
  final String title;
  final String description;
  final IconData? materialIcon;
  final bool isFaIcon;
  final String? requiredRole; // null=전체, 'admin'=임원진+, 'super_admin'=회장만
  final List<String> spotlightKeys; // 화면 내 강조할 요소 GlobalKey 이름들

  const OnboardingStep({
    required this.menuKey,
    required this.title,
    required this.description,
    this.materialIcon,
    this.isFaIcon = false,
    this.requiredRole,
    this.spotlightKeys = const [],
  });

  bool isVisibleForRole(String role) {
    if (requiredRole == null) return true;
    if (requiredRole == 'admin') return role == 'admin' || role == 'super_admin';
    if (requiredRole == 'super_admin') return role == 'super_admin';
    return false;
  }
}

const List<OnboardingStep> kOnboardingSteps = [
  OnboardingStep(
    menuKey: 'notice',
    title: '공지사항',
    description: '임원진이 올린 중요한 공지를 확인할 수 있어요. 오른쪽 위 [작성] 버튼으로 공지를 올려보세요.',
    isFaIcon: true,
    spotlightKeys: ['ob_notice_write'],
  ),
  OnboardingStep(
    menuKey: 'feed',
    title: '피드',
    description: '멤버들과 자유롭게 소통하는 공간이에요. 아래 버튼으로 글을 올려보세요!',
    materialIcon: Icons.dynamic_feed,
    spotlightKeys: ['ob_feed_fab'],
  ),
  OnboardingStep(
    menuKey: 'archive',
    title: '공연 기록',
    description: '지난 공연을 유튜브 링크와 함께 아카이브해요. + 버튼으로 기록을 추가해보세요.',
    materialIcon: Icons.videocam,
    spotlightKeys: ['ob_archive_add'],
  ),
  OnboardingStep(
    menuKey: 'challenge',
    title: '챌린지',
    description: '다른 동아리들과 경쟁하는 챌린지! 우리 동아리 영상을 제출해 순위를 올려봐요.',
    materialIcon: Icons.emoji_events,
    spotlightKeys: ['ob_challenge_submit'],
  ),
  OnboardingStep(
    menuKey: 'schedule',
    title: '무대 순서 최적화',
    description: 'AI가 팀 조합을 분석해 최적의 공연 순서를 짜줘요. 곡을 추가하고 최적화를 눌러보세요!',
    materialIcon: Icons.queue_music,
    requiredRole: 'admin',
    spotlightKeys: ['ob_schedule_add_song', 'ob_schedule_optimize'],
  ),
  OnboardingStep(
    menuKey: 'group',
    title: '스케줄 조율',
    description: '팀원들의 가능한 시간대를 모아 최적의 연습 시간을 찾아줘요. 먼저 방 코드를 추가해보세요!',
    materialIcon: Icons.group,
    spotlightKeys: ['ob_group_add_code'],
  ),
  OnboardingStep(
    menuKey: 'booking',
    title: '연습실 예약',
    description: '연습실 사용 시간을 팀별로 예약해요. 중복 예약은 자동으로 차단돼요!',
    materialIcon: Icons.meeting_room,
    spotlightKeys: ['ob_booking_add'],
  ),
  OnboardingStep(
    menuKey: 'audio',
    title: '음원 제출',
    description: '공연할 곡의 MR 파일을 미리 제출하고 관리해요. 공연 추가 버튼을 눌러보세요!',
    materialIcon: Icons.audio_file,
    spotlightKeys: ['ob_audio_add'],
  ),
  OnboardingStep(
    menuKey: 'clubManage',
    title: '동아리 관리',
    description: '플랜 관리부터 멤버 초대까지! 초대 코드를 복사해 멤버를 초대해보세요.',
    materialIcon: Icons.manage_accounts,
    requiredRole: 'super_admin',
    spotlightKeys: ['ob_club_plan', 'ob_club_invite'],
  ),
];
