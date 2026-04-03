import 'package:flutter/material.dart';

class OnboardingStep {
  final String menuKey;
  final String title;
  final String description;
  final IconData? materialIcon;
  final bool isFaIcon;
  final String? requiredRole; // null=전체, 'admin'=임원진+, 'super_admin'=회장만

  const OnboardingStep({
    required this.menuKey,
    required this.title,
    required this.description,
    this.materialIcon,
    this.isFaIcon = false,
    this.requiredRole,
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
    description: '임원진이 올린 중요한 공지를 바로 확인할 수 있어요',
    isFaIcon: true,
  ),
  OnboardingStep(
    menuKey: 'feed',
    title: '피드',
    description: '멤버들과 자유롭게 게시글을 올리고 소통해요',
    materialIcon: Icons.dynamic_feed,
  ),
  OnboardingStep(
    menuKey: 'archive',
    title: '공연 기록',
    description: '유튜브 영상과 함께 지난 공연 기록을 아카이브해요',
    materialIcon: Icons.videocam,
  ),
  OnboardingStep(
    menuKey: 'challenge',
    title: '챌린지',
    description: '다른 지역의 동아리들과 함께 챌린지에 참여해서 순위를 올려봐요',
    materialIcon: Icons.emoji_events,
  ),
  OnboardingStep(
    menuKey: 'schedule',
    title: '무대 순서 최적화',
    description: 'AI가 팀 조합을 분석해 최적의 공연 순서를 자동으로 짜줘요',
    materialIcon: Icons.queue_music,
    requiredRole: 'admin',
  ),
  OnboardingStep(
    menuKey: 'group',
    title: '스케줄 조율',
    description: '팀원들의 연습 가능한 시간대를 모아 딱 맞는 시간을 찾아줘요',
    materialIcon: Icons.group,
  ),
  OnboardingStep(
    menuKey: 'booking',
    title: '연습실 예약',
    description: '연습실 사용 시간을 팀별로 예약하고 겹침을 방지해요',
    materialIcon: Icons.meeting_room,
  ),
  OnboardingStep(
    menuKey: 'audio',
    title: '음원 제출',
    description: '공연할 곡의 MR 파일을 미리 제출하고 관리할 수 있어요',
    materialIcon: Icons.audio_file,
  ),
  OnboardingStep(
    menuKey: 'clubManage',
    title: '동아리 관리',
    description: '멤버 역할 변경, 동아리 프로필 수정 등 전체 설정을 관리해요',
    materialIcon: Icons.manage_accounts,
    requiredRole: 'super_admin',
  ),
];
