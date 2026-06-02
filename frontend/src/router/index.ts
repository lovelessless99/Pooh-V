import { createRouter, createWebHashHistory } from 'vue-router'
import CoverageView  from '@/views/CoverageView.vue'
import BanditView    from '@/views/BanditView.vue'
import ControlView   from '@/views/ControlView.vue'
import ScenariosView from '@/views/ScenariosView.vue'

const router = createRouter({
  history: createWebHashHistory(),
  routes: [
    { path: '/',           redirect: '/coverage' },
    { path: '/coverage',   component: CoverageView  },
    { path: '/bandit',     component: BanditView    },
    { path: '/control',    component: ControlView   },
    { path: '/scenarios',  component: ScenariosView },
  ]
})

export default router
