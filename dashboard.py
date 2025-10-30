import streamlit as st
import pandas as pd
import plotly.graph_objects as go
from datetime import datetime
import numpy as np

st.set_page_config(page_title="Agentic AI 로깅 시스템", layout="wide", page_icon="🔍")

st.markdown("""
<style>
    [data-testid="stAppViewContainer"] {
        background-color: #1a1d2e;
    }
    
    [data-testid="stSidebar"] {
        background-color: #16192b;
    }
    
    div[data-testid="stMetric"] {
        background: linear-gradient(135deg, #e8eaf6 0%, #d1d5f0 100%);
        padding: 1.5rem;
        border-radius: 1rem;
    }
    
    div[data-testid="stMetric"] label {
        color: #4a5568 !important;
        font-size: 0.9rem !important;
        font-weight: 500 !important;
    }
    
    div[data-testid="stMetric"] [data-testid="stMetricValue"] {
        color: #1a202c !important;
        font-size: 2.5rem !important;
        font-weight: 700 !important;
    }
    
    div[data-testid="stMetric"] [data-testid="stMetricDelta"] {
        font-size: 0.85rem !important;
        font-weight: 600 !important;
    }
    
    .block-container {
        padding-top: 2rem;
    }
    
    h3 {
        color: #e4e7eb;
        font-size: 1.25rem;
        font-weight: 600;
        margin-bottom: 1.5rem;
    }
</style>
""", unsafe_allow_html=True)

with st.sidebar:
    st.markdown("### 🔍 ByeWind")
    st.markdown("---")
    st.markdown("**Favorites**")
    st.markdown("• Overview")
    st.markdown("• Projects")
    st.markdown("---")
    st.markdown("**Dashboards**")
    st.markdown("• Overview")
    st.markdown("• eCommerce")
    st.markdown("• Projects")

st.title("MCP 로깅 시스템")
st.markdown("<br>", unsafe_allow_html=True)

col1, col2, col3, col4 = st.columns(4)

with col1:
    st.metric(
        label="총 로그 수",
        value="1,247",
        delta="+11.02%"
    )

with col2:
    st.metric(
        label="총 서버 요청",
        value="8,542",
        delta="-0.03%",
        delta_color="inverse"
    )

with col3:
    st.metric(
        label="활성 에이전트",
        value="24",
        delta="+15.03%"
    )

with col4:
    st.metric(
        label="시스템 안정성",
        value="94.6%",
        delta="+0.08%"
    )

st.markdown("<br><br>", unsafe_allow_html=True)

col_left, col_right = st.columns([1, 2])

with col_left:
    st.markdown("### 로그 상태")
    
    fig_donut = go.Figure(data=[go.Pie(
        labels=['성공', '진행중', '실패'],
        values=[67.6, 26.4, 6],
        hole=0.7,
        marker=dict(
            colors=['#7dd3c0', '#a8b8ff', '#f49e9e'],
            line=dict(color='#232736', width=4)
        ),
        textinfo='none',
        hovertemplate='<b>%{label}</b><br>%{value}%<extra></extra>'
    )])
    
    fig_donut.update_layout(
        showlegend=True,
        height=300,
        margin=dict(l=0, r=0, t=0, b=0),
        paper_bgcolor='rgba(0,0,0,0)',
        plot_bgcolor='rgba(0,0,0,0)',
        font=dict(color='#a0aec0', size=13),
        legend=dict(
            orientation="v",
            yanchor="middle",
            y=0.5,
            xanchor="left",
            x=1.1,
            bgcolor='rgba(255,255,255,0.05)',
            bordercolor='rgba(255,255,255,0.1)',
            borderwidth=1
        )
    )
    
    st.plotly_chart(fig_donut, use_container_width=True)

with col_right:
    st.markdown("### 로그 목록")
    
    df_logs = pd.DataFrame({
        '작업명': [
            '데이터베이스 쿼리',
            '파일 읽기 작업',
            'API 호출 및 처리',
            '리포트 생성',
            '웹 스크래핑'
        ],
        '담당자': ['A', 'B, C', 'D, E', 'F', 'G'],
        '소요시간': [
            '3시간 20분',
            '12시간 21분',
            '78시간 5분',
            '26시간 58분',
            '17시간 22분'
        ],
        '상태': ['진행중', '완료', '대기중', '승인됨', '거부됨']
    })
    
    def highlight_status(val):
        if val == '완료':
            color = '#48bb78'
            bg = 'rgba(72, 187, 120, 0.2)'
        elif val == '진행중':
            color = '#63b3ed'
            bg = 'rgba(99, 179, 237, 0.2)'
        elif val == '대기중' or val == '승인됨':
            color = '#ed8936'
            bg = 'rgba(237, 137, 54, 0.2)'
        else:
            color = '#f56565'
            bg = 'rgba(245, 101, 101, 0.2)'
        return f'background-color: {bg}; color: {color}; padding: 6px 12px; border-radius: 12px; font-weight: 600;'
    
    st.dataframe(
        df_logs.style.applymap(highlight_status, subset=['상태']),
        use_container_width=True,
        height=280
    )

st.markdown("<br><br>", unsafe_allow_html=True)

st.markdown("### 월별 로그 추이")

months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
values = [15000, 28000, 20000, 35000, 12000, 22000, 16000, 26598, 19000, 30000, 13000, 24000]
colors = ['#a8b8ff', '#7dd3c0', '#b8a8ff', '#8ec5fc', '#d4a8ff', '#7dd3c0', 
          '#a8b8ff', '#7dd3c0', '#b8a8ff', '#8ec5fc', '#d4a8ff', '#7dd3c0']

fig_bar = go.Figure(data=[go.Bar(
    x=months,
    y=values,
    marker=dict(
        color=colors,
        line=dict(width=0)
    ),
    hovertemplate='<b>%{x}</b><br>%{y:,}건<extra></extra>',
    width=0.6
)])

fig_bar.update_layout(
    height=300,
    margin=dict(l=0, r=0, t=10, b=0),
    paper_bgcolor='rgba(0,0,0,0)',
    plot_bgcolor='rgba(0,0,0,0)',
    font=dict(color='#a0aec0', size=11),
    xaxis=dict(
        showgrid=False,
        tickfont=dict(size=11)
    ),
    yaxis=dict(
        showgrid=True,
        gridcolor='rgba(255,255,255,0.05)',
        tickfont=dict(size=11),
        tickformat=','
    ),
    showlegend=False,
    hovermode='x'
)

st.plotly_chart(fig_bar, use_container_width=True)

with st.sidebar:
    st.markdown("---")
    st.markdown("### 알림")
    st.info("🐛 오류 수정 완료 - 방금 전")
    st.info("👤 새 에이전트 등록됨 - 39분 전")
    st.info("✅ 시스템 점검 완료 - 12시간 전")
    
    st.markdown("### 활동")
    st.info("🎨 설정 변경됨 - 방금 전")
    st.info("🚀 새 버전 배포됨 - 59분 전")
    st.info("🐛 버그 수정 제출됨 - 12시간 전")
    
    st.markdown("### 담당자")
    st.markdown("• Natali Craig")
    st.markdown("• Drew Cano")
    st.markdown("• Andi Lane")
    st.markdown("• Koray Okumus")
    st.markdown("• Kate Morrison")
    st.markdown("• Melody Macy")