// #screen-main —— 三栏任务界面：侧边栏 + 中央任务列表 + 详情面板。
// 对齐 design/web/index.html #screen-main 结构。

import { useEffect } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { GlobalDialogs } from '../components/dialogs'
import { DetailPanel } from '../components/tasks/DetailPanel'
import { ManageBar } from '../components/tasks/ManageBar'
import { Sidebar } from '../components/tasks/Sidebar'
import { StatusBar } from '../components/tasks/StatusBar'
import { StatusTabs } from '../components/tasks/StatusTabs'
import { TaskList } from '../components/tasks/TaskList'
import { TasksUiProvider, useTasksUi } from '../components/tasks/context'
import { TopBar } from '../components/tasks/TopBar'
import { api } from '../lib/api'
import { connectWs } from '../lib/ws'

export function TasksScreen() {
  const qc = useQueryClient()
  useEffect(() => {
    connectWs(qc)
  }, [qc])

  // 预取 + 与子组件共享同一份 Query 缓存（WS 消息直接 setQueryData 到这些 key）。
  useQuery({ queryKey: ['tasks'], queryFn: api.listTasks })
  useQuery({ queryKey: ['queues'], queryFn: api.listQueues })
  useQuery({ queryKey: ['stats'], queryFn: api.stats, refetchInterval: 30_000 })

  return (
    <TasksUiProvider>
      <section className="wscreen active" id="screen-main">
        <Sidebar />
        <SideBackdrop />
        <div className="center">
          <TopBar />
          <ManageBar />
          <StatusTabs />
          <TaskList />
          <StatusBar />
        </div>
        <DetailPanel />
      </section>
      <GlobalDialogs />
    </TasksUiProvider>
  )
}

/** 移动端抽屉侧边栏的遮罩：仅在小屏且抽屉展开时可见（CSS 控制），点击收起。 */
function SideBackdrop() {
  const { sidebarOpen, setSidebarOpen } = useTasksUi()
  if (!sidebarOpen) return null
  return <div className="side-backdrop" onClick={() => setSidebarOpen(false)} />
}
