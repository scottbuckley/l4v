(*
 * Copyright 2020, Data61, CSIRO (ABN 41 687 119 230)
 *
 * SPDX-License-Identifier: GPL-2.0-only
 *)

theory SchedContextInv_R
imports Invocations_R Tcb_R
begin

global_interpretation schedContextCompleteYieldTo: typ_at_all_props' "schedContextCompleteYieldTo scp"
  by typ_at_props'

context begin interpretation Arch . (*FIXME: arch_split*)

primrec valid_sc_inv' :: "sched_context_invocation \<Rightarrow> kernel_state \<Rightarrow> bool" where
  "valid_sc_inv' (InvokeSchedContextConsumed scptr args) =
     (sc_at' scptr and ex_nonz_cap_to' scptr and case_option \<top> valid_ipc_buffer_ptr' args)"
| "valid_sc_inv' (InvokeSchedContextBind scptr cap) =
     (ex_nonz_cap_to' scptr and valid_cap' cap and
        (case cap of
           ThreadCap t \<Rightarrow>
             ex_nonz_cap_to' t and
             bound_sc_tcb_at' ((=) None) t and
             obj_at' (\<lambda>sc. scTCB sc = None) scptr \<^cancel>\<open> and
             FIXME RT: can hopefully be established via assertions:
             (\<lambda>s. st_tcb_at' (ipc_queued_thread_state) t s
                     \<longrightarrow> sc_at_pred' (sc_released (cur_time s)) scptr s) \<close>
         | NotificationCap n _ _ _ \<Rightarrow>
             ex_nonz_cap_to' n and
             obj_at' (\<lambda>ntfn. ntfnSc ntfn = None) n and
             obj_at' (\<lambda>sc. scNtfn sc = None) scptr
         | _ \<Rightarrow> \<bottom>))"
| "valid_sc_inv' (InvokeSchedContextUnbindObject scptr cap) =
     (ex_nonz_cap_to' scptr and valid_cap' cap and
        (case cap of
           ThreadCap t \<Rightarrow>
             ex_nonz_cap_to' t and obj_at' (\<lambda>sc. scTCB sc = Some t) scptr and
             (\<lambda>s. t \<noteq> ksCurThread s)
         | NotificationCap n _ _ _ \<Rightarrow>
             ex_nonz_cap_to' n and obj_at' (\<lambda>sc. scNtfn sc = Some n) scptr
         | _ \<Rightarrow> \<bottom>))"
| "valid_sc_inv' (InvokeSchedContextUnbind scptr) = (sc_at' scptr and ex_nonz_cap_to' scptr)"
| "valid_sc_inv' (InvokeSchedContextYieldTo scptr args) =
     (\<lambda>s. ex_nonz_cap_to' scptr s
          \<and> case_option \<top> valid_ipc_buffer_ptr' args s
          \<and> (\<forall>ct. ct = ksCurThread s \<longrightarrow>
                bound_yt_tcb_at' ((=) None) ct s \<and>
                obj_at' (\<lambda>sc. \<exists>t. scTCB sc = Some t \<and> t \<noteq> ct) scptr s))"

definition
  valid_refills_number' :: "nat \<Rightarrow> nat \<Rightarrow> bool"
where
  "valid_refills_number' max_refills n \<equiv> max_refills \<le> refillAbsoluteMax' n"

primrec valid_sc_ctrl_inv' :: "sched_control_invocation \<Rightarrow> kernel_state \<Rightarrow> bool" where
  "valid_sc_ctrl_inv' (InvokeSchedControlConfigureFlags scptr budget period mrefills badge flags) =
     ((\<lambda>s. \<exists>n. sc_at'_n n scptr s \<and> valid_refills_number' mrefills n) and
      ex_nonz_cap_to' scptr and K (MIN_REFILLS \<le> mrefills) and
      K (budget \<le> MAX_PERIOD \<and> budget \<ge> MIN_BUDGET \<and>
         period \<le> MAX_PERIOD \<and> budget \<ge> MIN_BUDGET \<and>
         budget \<le> period))"

primrec sc_inv_rel :: "Invocations_A.sched_context_invocation \<Rightarrow> sched_context_invocation \<Rightarrow> bool"
  where
  "sc_inv_rel (Invocations_A.InvokeSchedContextConsumed sc_ptr bf) sci' =
   (sci' = InvokeSchedContextConsumed sc_ptr bf)"
| "sc_inv_rel (Invocations_A.InvokeSchedContextBind sc_ptr cap) sci' =
   (\<exists>cap'. cap_relation cap cap' \<and> sci' = InvokeSchedContextBind sc_ptr cap')"
| "sc_inv_rel (Invocations_A.InvokeSchedContextUnbindObject sc_ptr cap) sci' =
   (\<exists>cap'. cap_relation cap cap' \<and> sci' = InvokeSchedContextUnbindObject sc_ptr cap')"
| "sc_inv_rel (Invocations_A.InvokeSchedContextUnbind sc_ptr) sci' =
   (sci' = InvokeSchedContextUnbind sc_ptr)"
| "sc_inv_rel (Invocations_A.InvokeSchedContextYieldTo sc_ptr bf) sci' =
   (sci' = InvokeSchedContextYieldTo sc_ptr bf)"

primrec sc_ctrl_inv_rel ::
  "Invocations_A.sched_control_invocation \<Rightarrow> sched_control_invocation \<Rightarrow> bool" where
  "sc_ctrl_inv_rel (Invocations_A.InvokeSchedControlConfigureFlags sc_ptr budget period refills badge flags) sci' =
    (sci' = InvokeSchedControlConfigureFlags sc_ptr budget period refills badge flags)"

lemma decodeSchedContext_Bind_wf:
  "\<lbrace>\<lambda>s. \<exists>n. valid_cap' (SchedContextCap sc_ptr n) s
        \<and> ex_nonz_cap_to' sc_ptr s
        \<and> (\<forall>cap\<in>set excaps. \<forall>r\<in>zobj_refs' cap. ex_nonz_cap_to' r s)
        \<and> (\<forall>x\<in>set excaps. valid_cap' x s)\<rbrace>
   decodeSchedContext_Bind sc_ptr excaps
   \<lbrace>valid_sc_inv'\<rbrace>, -"
  apply (clarsimp simp: decodeSchedContext_Bind_def)
  apply (wpsimp wp: gts_wp' threadGet_wp getNotification_wp
              simp: scReleased_def scActive_def isBlocked_def refillReady_def)
  apply (clarsimp simp: valid_cap'_def)
  apply (drule_tac x="hd excaps" in bspec, fastforce dest: hd_in_set)+
  apply (fastforce simp: pred_tcb_at'_def obj_at'_def)
  done

lemma decodeSchedContext_UnbindObject_wf:
  "\<lbrace>\<lambda>s. \<exists>n. valid_cap' (SchedContextCap sc_ptr n) s
        \<and> ex_nonz_cap_to' sc_ptr s
        \<and> (\<forall>cap\<in>set excaps. \<forall>r\<in>zobj_refs' cap. ex_nonz_cap_to' r s)
        \<and> (\<forall>x\<in>set excaps. valid_cap' x s)\<rbrace>
   decodeSchedContext_UnbindObject sc_ptr excaps
   \<lbrace>valid_sc_inv'\<rbrace>, -"
  apply (clarsimp simp: decodeSchedContext_UnbindObject_def)
  apply (wpsimp wp: gts_wp' threadGet_wp getNotification_wp
              simp: scReleased_def scActive_def isBlocked_def refillReady_def)
  apply (clarsimp simp: valid_cap'_def)
  apply (drule_tac x="hd excaps" in bspec, fastforce dest: hd_in_set)+
  apply (fastforce simp: pred_tcb_at'_def obj_at'_def)
  done

lemma decodeSchedContext_YieldTo_wf:
  "\<lbrace>\<lambda>s. \<exists>n. valid_cap' (SchedContextCap sc_ptr n) s \<and> ex_nonz_cap_to' sc_ptr s
        \<and> case_option \<top> valid_ipc_buffer_ptr' args s\<rbrace>
   decodeSchedContext_YieldTo sc_ptr args
   \<lbrace>valid_sc_inv'\<rbrace>, -"
  apply (clarsimp simp: decodeSchedContext_YieldTo_def)
  apply (wpsimp wp: gts_wp' threadGet_wp getNotification_wp getTCB_wp
              simp: scReleased_def scActive_def isBlocked_def refillReady_def)
  apply (clarsimp simp: valid_cap'_def)
  apply (clarsimp simp: pred_tcb_at'_def obj_at'_def projectKOs)
  done

lemma decodeSchedContextInvocation_wf:
  "\<lbrace>\<lambda>s. \<exists>n. valid_cap' (SchedContextCap sc_ptr n) s
        \<and> ex_nonz_cap_to' sc_ptr s
        \<and> case_option \<top> valid_ipc_buffer_ptr' args s
        \<and> (\<forall>cap\<in>set excaps. \<forall>r\<in>zobj_refs' cap. ex_nonz_cap_to' r s)
        \<and> (\<forall>x\<in>set excaps. valid_cap' x s)\<rbrace>
   decodeSchedContextInvocation label sc_ptr excaps args
   \<lbrace>valid_sc_inv'\<rbrace>, -"
  apply (simp add: decodeSchedContextInvocation_def)
  apply (wpsimp wp: decodeSchedContext_Bind_wf
                    decodeSchedContext_UnbindObject_wf
                    decodeSchedContext_YieldTo_wf)
  apply (fastforce dest: valid_SchedContextCap_sc_at')
  done

lemma decodeSchedControlInvocation_wf:
  "\<lbrace>invs' and (\<lambda>s. \<forall>cap\<in>set excaps. \<forall>r\<in>zobj_refs' cap. ex_nonz_cap_to' r s)
    and (\<lambda>s. \<forall>x\<in>set excaps. valid_cap' x s)\<rbrace>
   decodeSchedControlInvocation label args excaps
   \<lbrace>valid_sc_ctrl_inv'\<rbrace>, -"
  apply (clarsimp simp: decodeSchedControlInvocation_def)
  apply (case_tac "genInvocationType label"; simp; (solves wpsimp)?)
  apply (wpsimp simp: decodeSchedControl_ConfigureFlags_def)
  apply (cases excaps; simp)
  apply (rename_tac a list, case_tac a; simp add: isSchedContextCap_def)
  apply (clarsimp simp: valid_cap'_def  ko_wp_at'_def scBits_simps valid_refills_number'_def
                        MAX_PERIOD_def maxPeriodUs_def usToTicks_def us_to_ticks_mono
                        MIN_BUDGET_def kernelWCET_ticks_def timeArgSize_def minBudgetUs_def
                        MIN_REFILLS_def minRefills_def not_less
                  cong: conj_cong)
  apply (insert getCurrentTime_buffer_bound)
  apply (intro conjI impI; (fastforce intro: us_to_ticks_mono)?)
   apply (rule_tac order_trans[OF MIN_BUDGET_helper])
   apply (rule us_to_ticks_mono)
    apply blast
   apply (fastforce intro: order_trans[OF mult_le_mono1]
                     simp: word_le_nat_alt)
  apply (fastforce intro: order_trans[OF mult_le_mono1] us_to_ticks_mono
                    simp: word_le_nat_alt)
  done

lemma decodeSchedcontext_Bind_corres:
  "list_all2 cap_relation excaps excaps'
   \<Longrightarrow> corres (ser \<oplus> sc_inv_rel)
         (invs and valid_sched and sc_at sc_ptr and (\<lambda>s. \<forall>x\<in>set excaps. s \<turnstile> x))
         (invs' and (\<lambda>s. \<forall>x\<in>set excaps'. valid_cap' x s))
         (decode_sched_context_bind sc_ptr excaps)
         (decodeSchedContext_Bind sc_ptr excaps')"
  apply (clarsimp simp: decode_sched_context_bind_def decodeSchedContext_Bind_def)
  apply (cases excaps; clarsimp)
  apply (rename_tac cap list)
  apply (cases excaps'; clarsimp)
  apply (rule corres_splitEE'')
     apply (corressimp corres: get_sc_corres)
     apply (fastforce intro: sc_at'_cross_rel[unfolded cross_rel_def, rule_format])
    apply (rule liftE_validE[THEN iffD2, OF get_sched_context_sp])
   apply (rule liftE_validE[THEN iffD2, OF get_sc_sp'])
  apply (case_tac cap; clarsimp)
   apply (clarsimp simp: bindE_assoc)
   apply (rule corres_splitEE_skip; (solves wpsimp)?)
    apply (corressimp simp: sc_relation_def)
   apply (rule corres_splitEE''[where r'="(=)"]; (solves wpsimp)?)
    apply (corressimp corres: getNotification_corres
                        simp: get_sk_obj_ref_def ntfn_relation_def valid_cap_def valid_cap'_def
                          wp: hoare_vcg_all_lift)
   apply (rule corres_splitEE_skip; (solves wpsimp)?)
    apply (corressimp corres: getNotification_corres
                        simp: get_sk_obj_ref_def sc_relation_def)
   apply (clarsimp simp: returnOk_def)
  apply (clarsimp simp: bindE_assoc get_tcb_obj_ref_def)
  apply (rule corres_splitEE_skip; (solves wpsimp)?)
   apply (corressimp simp: sc_relation_def)
  apply (rule corres_splitEE''[where r'="(=)"])
     apply (subst corres_liftE_rel_sum)
     apply (rule corres_guard_imp)
       apply (rule threadGet_corres)
       apply (clarsimp simp: tcb_relation_def)
      apply (clarsimp simp: valid_cap_def)
     apply (clarsimp simp: valid_cap'_def)
    apply (rule liftE_validE[THEN iffD2, OF thread_get_sp])
   apply (rule liftE_validE[THEN iffD2, OF threadGet_sp])
  apply (rule corres_splitEE_skip; (solves \<open>wpsimp simp: valid_cap'_def obj_at'_def\<close>)?)
   apply (corressimp corres: getNotification_corres
                       simp: get_sk_obj_ref_def sc_relation_def)
  apply (rule corres_guard_imp)
    apply (rule corres_split_eqrE)
       apply (rule corres_splitEE)
          apply (rule whenE_throwError_corres)
            apply simp
           apply simp
          apply (clarsimp simp: returnOk_def)
         apply (subst corres_liftE_rel_sum)
         apply (rule corres_rel_imp)
          apply (rule isBlocked_corres)
         apply simp
        apply wpsimp
       apply wpsimp
      apply (rule corres_liftE_rel_sum[THEN iffD2, OF get_sc_released_corres])
     apply wpsimp
    apply (wpsimp simp: scReleased_def scActive_def)
   apply (fastforce simp: obj_at_def is_tcb_def)
  apply (clarsimp simp: obj_at'_def)
  done

lemma decodeSchedContext_UnbindObject_corres:
  "list_all2 cap_relation excaps excaps'
   \<Longrightarrow> corres (ser \<oplus> sc_inv_rel)
         (invs and sc_at sc_ptr)
         invs'
         (decode_sched_context_unbind_object sc_ptr excaps)
         (decodeSchedContext_UnbindObject sc_ptr excaps')"
  apply (clarsimp simp: decode_sched_context_unbind_object_def decodeSchedContext_UnbindObject_def)
  apply (cases excaps; clarsimp)
  apply (rename_tac cap list)
  apply (cases excaps'; clarsimp)
  apply (case_tac cap; clarsimp)
   apply (clarsimp simp: bindE_assoc get_sc_obj_ref_def liftE_bind_return_bindE_returnOk)
   apply (rule corres_splitEE'')
      apply (corressimp corres: get_sc_corres)
      apply (fastforce intro: sc_at'_cross_rel[unfolded cross_rel_def, rule_format])
     apply (rule liftE_validE[THEN iffD2, OF get_sched_context_sp])
    apply (rule liftE_validE[THEN iffD2, OF get_sc_sp'])
   apply (corressimp simp: sc_relation_def)
   apply (clarsimp simp: bindE_assoc get_sc_obj_ref_def liftE_bind_return_bindE_returnOk)
  apply (rule corres_splitEE'')
     apply (corressimp corres: get_sc_corres)
     apply (fastforce intro: sc_at'_cross_rel[unfolded cross_rel_def, rule_format])
    apply (rule liftE_validE[THEN iffD2, OF get_sched_context_sp])
   apply (rule liftE_validE[THEN iffD2, OF get_sc_sp'])
  apply (rule corres_splitEE'')
     apply (corressimp simp: sc_relation_def)
    apply (rule whenE_throwError_sp[simplified validE_R_def])+
  apply (rule corres_splitEE'')
     apply (corressimp corres: getCurThread_corres)
    apply (rule liftE_validE[THEN iffD2, OF gets_sp])
   apply (rule liftE_validE[THEN iffD2, OF getCurThread_sp])
  apply corressimp
  done

lemma decodeSchedContext_YieldTo_corres:
  "corres (ser \<oplus> sc_inv_rel)
          (invs and sc_at sc_ptr)
          invs'
          (decode_sched_context_yield_to sc_ptr args')
          (decodeSchedContext_YieldTo sc_ptr args')"
  apply add_cur_tcb'
  apply (clarsimp simp: decode_sched_context_yield_to_def decodeSchedContext_YieldTo_def)
  apply (clarsimp simp: bindE_assoc get_sc_obj_ref_def liftE_bind_return_bindE_returnOk)
  apply (rule corres_splitEE'')
     apply (corressimp corres: get_sc_corres)
     apply (fastforce intro: sc_at'_cross_rel[unfolded cross_rel_def, rule_format])
    apply (rule liftE_validE[THEN iffD2, OF get_sched_context_sp])
   apply (rule liftE_validE[THEN iffD2, OF get_sc_sp'])
  apply (rule corres_splitEE'')
     apply (corressimp simp: sc_relation_def)
    apply (rule whenE_throwError_sp[simplified validE_R_def])+
  apply (rule corres_splitEE'')
     apply (corressimp corres: getCurThread_corres)
    apply (rule liftE_validE[THEN iffD2, OF gets_sp])
   apply (rule liftE_validE[THEN iffD2, OF getCurThread_sp])
  apply (rule corres_splitEE_skip; (solves wpsimp)?)
   apply (corressimp simp: sc_relation_def)
  apply (clarsimp simp: sc_relation_def)
  apply (rule corres_splitEE''[where r'="(=)"])
     apply (subst corres_liftE_rel_sum)
     apply (rule corres_guard_imp)
       apply (rule threadGet_corres)
       apply (clarsimp simp: tcb_relation_def)
      apply (fastforce dest: invs_valid_objs valid_objs_ko_at
                       simp: valid_obj_def valid_sched_context_def)
     apply (fastforce dest: sc_ko_at_valid_objs_valid_sc'
                      simp: valid_sched_context'_def)
    apply (rule liftE_validE[THEN iffD2, OF thread_get_sp])
   apply (rule liftE_validE[THEN iffD2, OF threadGet_sp])
  apply (rule corres_splitEE''[where r'="(=)"])
     apply (subst corres_liftE_rel_sum)
     apply (rule corres_guard_imp)
       apply (rule threadGet_corres)
       apply (clarsimp simp: tcb_relation_def)
      apply fastforce
     apply (fastforce simp: cur_tcb'_def)
    apply (rule liftE_validE[THEN iffD2, OF thread_get_sp])
   apply (rule liftE_validE[THEN iffD2, OF threadGet_sp])
  apply (rule corres_splitEE_skip; corressimp)
  apply (rule corres_splitEE''[where r'="(=)"])
     apply (subst corres_liftE_rel_sum)
     apply (rule corres_guard_imp)
       apply (rule threadGet_corres)
       apply (clarsimp simp: tcb_relation_def)
      apply fastforce
     apply fastforce
    apply (rule liftE_validE[THEN iffD2, OF thread_get_sp])
   apply (rule liftE_validE[THEN iffD2, OF threadGet_sp])
  apply (rule corres_splitEE_skip; corressimp)
  apply (clarsimp simp: obj_at'_def)
  done

lemma decode_sc_inv_corres:
  "list_all2 cap_relation excaps excaps' \<Longrightarrow>
   corres (ser \<oplus> sc_inv_rel)
          (invs and valid_sched and sc_at sc_ptr and (\<lambda>s. \<forall>x\<in>set excaps. s \<turnstile> x)
           and case_option \<top> in_user_frame args')
          (invs' and (\<lambda>s. \<forall>x\<in>set excaps'. valid_cap' x s)
           and case_option \<top> valid_ipc_buffer_ptr' args')
          (decode_sched_context_invocation (mi_label mi) sc_ptr excaps args')
          (decodeSchedContextInvocation (mi_label mi) sc_ptr excaps' args')"
  apply (clarsimp simp: decode_sched_context_invocation_def decodeSchedContextInvocation_def
             split del: if_split)
  apply (cases "gen_invocation_type (mi_label mi)"
         ; clarsimp split: gen_invocation_labels.split list.splits
                split del: if_split)
      apply (clarsimp simp: returnOk_def)
     apply (corressimp corres: decodeSchedcontext_Bind_corres)
    defer
    apply (corressimp corres: decodeSchedContext_UnbindObject_corres)
   apply (corressimp corres: decodeSchedContext_YieldTo_corres)
  apply (rule corres_splitEE'')
     apply (corressimp corres: get_sc_corres)
     apply (fastforce intro: sc_at'_cross_rel[unfolded cross_rel_def, rule_format])
    apply (rule liftE_validE[THEN iffD2, OF get_sched_context_sp])
   apply (rule liftE_validE[THEN iffD2, OF get_sc_sp'])
  apply (rule corres_splitEE'')
     apply (corressimp corres: getCurThread_corres)
    apply (rule liftE_validE[THEN iffD2, OF gets_sp])
   apply (rule liftE_validE[THEN iffD2, OF getCurThread_sp])
  apply (rule corres_splitEE_skip; corressimp)
  apply (clarsimp simp: sc_relation_def)
  done

lemma decode_sc_ctrl_inv_corres:
  "list_all2 cap_relation excaps excaps' \<Longrightarrow>
   corres (ser \<oplus> sc_ctrl_inv_rel) \<top> \<top>
          (decode_sched_control_invocation_flags (mi_label mi) args' excaps)
          (decodeSchedControlInvocation (mi_label mi) args' excaps')"
  apply (clarsimp simp: decode_sched_control_invocation_flags_def decodeSchedControlInvocation_def)
  apply (cases "gen_invocation_type (mi_label mi)"
         ; clarsimp simp: decodeSchedControl_ConfigureFlags_def TIME_ARG_SIZE_def timeArgSize_def)
  apply (cases excaps; clarsimp)
  apply (rename_tac cap list)
  apply (cases excaps'; clarsimp)
  apply (rule corres_splitEE_skip; (solves wpsimp)?)
   apply corressimp
  apply (rule corres_splitEE'')
      apply corressimp
     apply (case_tac cap; clarsimp simp: isSchedContextCap_def)
    apply (rule whenE_throwError_sp[simplified validE_R_def])+
  apply corressimp
  apply (auto simp: minBudgetUs_def MIN_BUDGET_US_def maxPeriodUs_def parse_time_arg_def
                    parseTimeArg_def usToTicks_def minRefills_def MIN_REFILLS_def
                    max_num_refills_eq_refillAbsoluteMax' refillAbsoluteMax_def max_refills_cap_def
             split: cap.splits)
  done

lemma schedContextBindNtfn_corres:
  "corres dc
     (valid_objs and sc_ntfn_sc_at ((=) None) scp
      and (obj_at (\<lambda>ko. \<exists>ntfn. ko = Notification ntfn \<and> ntfn_sc ntfn = None) ntfnp))
     (ntfn_at' ntfnp and sc_at' scp)
     (sched_context_bind_ntfn scp ntfnp) (schedContextBindNtfn scp ntfnp)"
  unfolding sched_context_bind_ntfn_def schedContextBindNtfn_def
  apply (clarsimp simp: update_sk_obj_ref_def bind_assoc)
  apply (rule corres_guard_imp)
    apply (rule corres_split[OF getNotification_corres])
      apply (rule corres_guard_imp)
        apply (rule corres_split[OF setNotification_corres])
           apply (clarsimp simp: ntfn_relation_def split: Structures_A.ntfn.splits)
          apply (fold updateSchedContext_def)
          apply (rule updateSchedContext_corres)
            apply (clarsimp simp: opt_map_red obj_at_simps is_sc_obj)
            apply (drule (1) pspace_relation_absD[OF _ state_relation_pspace_relation])
            apply (clarsimp simp: sc_relation_def)
           apply (clarsimp simp: opt_map_red obj_at_simps is_sc_obj)
           apply (drule (1) sc_replies_relation_prevs_list'[OF state_relation_sc_replies_relation])
           apply (clarsimp simp: opt_map_red)
          apply (clarsimp simp: objBits_simps')
         apply wpsimp
        apply wpsimp
       apply simp+
     apply wpsimp+
   apply (fastforce simp: obj_at_simps sc_ntfn_sc_at_def is_ntfn is_sc_obj valid_obj_def)
  apply clarsimp
  done

crunches tcb_sched_action, complete_yield_to, reschedule_required, sched_context_resume
  for in_user_frame[wp]: "in_user_frame buf"
  (simp: crunch_simps wp: crunch_wps ignore: set_tcb_obj_ref)

lemma
  schedContext_valid_ipc_buffer_ptr'[wp]:
  "setSchedContext scp sc \<lbrace>valid_ipc_buffer_ptr' x\<rbrace>" and
  threadSet_valid_ipc_buffer_ptr'[wp]:
  "threadSet f tp \<lbrace>valid_ipc_buffer_ptr' x\<rbrace>" and
  modifyReadyQueuesL1Bitmap_valid_ipc_buffer_ptr'[wp]:
  "modifyReadyQueuesL1Bitmap d g \<lbrace>valid_ipc_buffer_ptr' x\<rbrace>" and
  modifyReadyQueuesL2Bitmap_valid_ipc_buffer_ptr'[wp]:
  "modifyReadyQueuesL2Bitmap d n g \<lbrace>valid_ipc_buffer_ptr' x\<rbrace>" and
  setQueue_valid_ipc_buffer_ptr'[wp]:
  "setQueue d prio p \<lbrace>valid_ipc_buffer_ptr' x\<rbrace>"
  unfolding valid_ipc_buffer_ptr'_def
  by wpsimp+

crunches schedContextCompleteYieldTo, tcbSchedEnqueue, tcbSchedDequeue,
         rescheduleRequired, schedContextResume
  for valid_ipc_buffer_ptr'[wp]: "valid_ipc_buffer_ptr' buf"
  and sc_at'[wp]: "sc_at' scp"
  and cur_tcb'[wp]: cur_tcb'
  (simp: crunch_simps wp: crunch_wps threadSet_cur ignore: setSchedContext)

lemma threadSet_tcbYieldTo_update_valid_queues:
  "threadSet (tcbYieldTo_update f) t \<lbrace>valid_queues\<rbrace>"
  apply (simp add: threadSet_def)
  apply wp
   apply (simp add: valid_queues_def valid_queues_no_bitmap_def' pred_tcb_at'_def)
   apply (wp hoare_Ball_helper
             hoare_vcg_all_lift
             setObject_tcb_strongest)[1]
  apply (wp getObject_tcb_wp)
  apply (clarsimp simp: valid_queues_def valid_queues_no_bitmap_def' pred_tcb_at'_def)
  apply (fastforce simp: obj_at'_def projectKOs inQ_def)
  done

lemma sc_yield_from_update_sc_tcb_sc_at[wp]:
  "set_sc_obj_ref sc_yield_from_update scp ptr \<lbrace>sc_tcb_sc_at P scp\<rbrace>"
  apply (wpsimp wp: update_sched_context_wp)
  by (clarsimp simp: sc_tcb_sc_at_def obj_at_def)

lemma schedContextYieldTo_corres:
  "corres dc
      ((case_option \<top> in_user_frame buf and einvs) and
       (\<lambda>s. bound_yt_tcb_at ((=) None) (cur_thread s) s
            \<and> sc_tcb_sc_at (\<lambda>sctcb. \<exists>t. sctcb = Some t \<and> t \<noteq> cur_thread s) scp s))
      ((case_option \<top> valid_ipc_buffer_ptr' buf and invs') and
       (\<lambda>s. bound_yt_tcb_at' ((=) None) (ksCurThread s) s \<and>
                  obj_at' (\<lambda>sc. \<exists>t. scTCB sc = Some t \<and> t \<noteq> ksCurThread s) scp s))
      (sched_context_yield_to scp buf) (schedContextYieldTo scp buf)"
  (is "corres _ (?abs_buf and (\<lambda>s. ?ct s \<and> ?scp s)) (?con_buf and ?scp') _ _")
  apply add_cur_tcb'
  unfolding sched_context_yield_to_def schedContextYieldTo_def get_sc_obj_ref_def bind_assoc
    contextYieldToUpdateQueues_def
  apply (rule corres_guard_imp)
    apply (rule corres_split[OF get_sc_corres])
      apply (rename_tac sc sc')
      apply (rule_tac P="?abs_buf and ?ct and ?scp and (\<lambda>s. \<exists>n. ko_at (Structures_A.SchedContext sc n) scp s)"
                 and P'="?con_buf and cur_tcb' and ko_at' sc' scp"
             in corres_inst)
      apply simp
      apply (erule exE)
      apply (rule corres_split'[where r'=dc])
         apply (simp only: when_def fromJust_def)
         apply (rule corres_guard_imp)
           apply (rule corres_if2)
             apply (clarsimp simp: sc_relation_def)
            apply (rule_tac F="scYieldFrom sc' = sc_yield_from sc" in corres_req)
             apply (clarsimp simp: sc_relation_def)
            apply (rule_tac P="?abs_buf and ?ct and ?scp
                               and (\<lambda>s. \<exists>n. ko_at (Structures_A.SchedContext sc n) scp s)
                               and K (bound (sc_yield_from sc))"
                       and P'="?con_buf and cur_tcb' and ko_at' sc' scp"
                   in corres_inst)
            apply (rule corres_gen_asm')
            apply (erule exE, simp only: option.sel)
            apply (rule corres_guard_imp)
              apply (rule corres_bind_return2)
              apply (rule corres_split[OF schedContextCompleteYieldTo_corres])
                apply (rule_tac P="?abs_buf and ?ct and ?scp and sc_yf_sc_at ((=) None) scp"
                           and P'="?con_buf and cur_tcb'"
                       in corres_inst)
                apply simp
                apply (rule corres_symb_exec_l)
                   apply (rename_tac sc'')
                   apply (rule corres_bind_return)
                   apply (rule corres_assert_assume_l)
                   apply simp
                  apply (wpsimp wp: get_sched_context_exs_valid simp: sc_yf_sc_at_def obj_at_def)
                 apply (wpsimp simp: sc_yf_sc_at_def obj_at_def)
                apply (wpsimp simp: sc_yf_sc_at_def obj_at_def)
               supply if_split[split del]
               apply ((wpsimp wp: complete_yield_to_sc_yf_sc_at_None hoare_case_option_wp
                                  complete_yield_to_invs complete_yield_to_sc_tcb_sc_at
                     | wps)+)[1]
              apply (wpsimp wp: hoare_case_option_wp)
             apply clarsimp
             apply (fastforce simp: valid_obj_def valid_sched_context_def obj_at_def sc_yf_sc_at_def
                             dest!: invs_valid_objs)
            apply clarsimp
            apply (fastforce simp: valid_obj'_def valid_sched_context'_def obj_at'_def projectKOs
                            dest!: invs_valid_objs')

           apply (rule_tac P="?abs_buf and sc_at scp"
                      and P'="?con_buf and cur_tcb' and sc_at' scp" in corres_inst)
           apply simp
          apply (clarsimp simp: sc_yf_sc_at_def sc_tcb_sc_at_def obj_at_def is_sc_obj)
          apply (fastforce dest!: invs_valid_objs simp: valid_obj_def valid_sched_context_def obj_at_def)
         apply clarsimp
        apply simp
        apply (rule_tac P="?abs_buf and sc_yf_sc_at ((=) None) scp and ?ct and ?scp"
                   and P'="?con_buf and cur_tcb' and sc_at' scp"
               in corres_inst)
        apply (rule corres_guard_imp)
          apply (rule corres_split[OF schedContextResume_corres])
            apply (rule corres_split[OF get_sc_corres _ get_sched_context_wp getSchedContext_wp])
            apply (rename_tac sc0 sc0')
            apply (rule_tac F="scTCB sc0' = sc_tcb sc0" in corres_req)
             apply (clarsimp simp: sc_relation_def)
            apply (rule corres_assert_opt_assume_l)
            apply (rule_tac P="?abs_buf and sc_yf_sc_at ((=) None) scp and ?ct and ?scp
                               and (\<lambda>s. \<exists>n. ko_at (Structures_A.SchedContext sc0 n) scp s)
                               and K (bound (sc_tcb sc0))"
                       and P'="?con_buf and cur_tcb' and ko_at' sc0' scp"
                   in corres_inst)
            apply (rule corres_gen_asm')
            apply (elim exE)
            apply (rename_tac tp)
            apply (simp only: option.sel pred_conj_def simp_thms(21))
            apply (rule corres_guard_imp)
              apply (rule corres_split_eqr[OF _ isSchedulable_corres])
                apply (rename_tac sched)
                apply (rule corres_split_eqr)
                   apply (rule corres_when, simp)
                   apply (rule setConsumed_corres)
                  apply (rule_tac P="?abs_buf and sc_yf_sc_at ((=) None) scp and ?ct and ?scp
                                     and (\<lambda>s. sched = schedulable tp s) and tcb_at tp
                                     and sc_tcb_sc_at ((=) (Some tp)) scp"
                             and P'="?con_buf and cur_tcb' and tcb_at' tp and ko_at' sc0' scp
                                     and (\<lambda>s. scTCBs_of s scp = Some tp)"
                         in corres_inst)
                  apply (rule corres_guard_imp)
                    apply (rule corres_if2, simp)
                     apply (rule corres_split_eqr[OF _ getCurThread_corres])
                       apply (rename_tac ct_ptr)
                       apply (rule corres_split_eqr[OF _ threadGet_corres])
                          apply (rule corres_split_eqr[OF _ threadGet_corres])
                             apply (rule corres_if2)
                               apply simp
                              apply simp
                              apply (rule corres_split[OF tcbSchedDequeue_corres])
                                apply (rule corres_split[OF tcbSchedEnqueue_corres])
                                  apply simp
                                 apply (wpsimp wp: tcbSchedDequeue_valid_queues)+
                             apply (rule corres_split[OF tcb_yield_to_update_corres])
                               apply (rule_tac sc'1=sc0' in corres_split[OF update_sc_no_reply_stack_update_ko_at'_corres])
                                     apply ((clarsimp simp: sc_relation_def objBits_simps')+)[4]
                                 apply (rule_tac P="valid_objs and pspace_aligned and pspace_distinct
                                                    and weak_valid_sched_action and active_sc_valid_refills
                                                    and sc_yf_sc_at ((=) (Some ct_ptr)) scp and ?scp
                                                    and bound_yt_tcb_at ((=) (Some scp)) ct_ptr
                                                    and tcb_at ct_ptr and tcb_at tp
                                                    and sc_tcb_sc_at ((=) (Some tp)) scp"
                                            and P'="valid_objs' and valid_queues and valid_queues' and cur_tcb'
                                                    and valid_release_queue_iff and tcb_at' tp and sc_at' scp
                                                    and obj_at' (\<lambda>sc. scYieldFrom sc = Some ct_ptr) scp
                                                    and (\<lambda>s. scTCBs_of s scp = Some tp)"
                                        in corres_inst)
                                 apply (rule corres_guard_imp)
                                   apply (rule corres_split[OF tcbSchedDequeue_corres])
                                     apply (rule corres_split[OF tcbSchedEnqueue_corres])
                                       apply (rule corres_split[OF tcbSchedEnqueue_corres])
                                         apply (rule corres_split[OF rescheduleRequired_corres])
                                           apply simp
                                          apply (wpsimp wp: tcbSchedDequeue_valid_queues)+
                                 apply (clarsimp simp: obj_at'_def projectKOs valid_objs'_valid_tcbs')
                                 apply (prop_tac "\<exists>tcb. ko_at' tcb tp s")
                                  apply (fastforce simp: valid_obj'_def valid_sched_context'_def obj_at'_def)
                                 apply clarsimp
                                 apply (drule (1) tcb_ko_at_valid_objs_valid_tcb'[rotated])
                                 apply (clarsimp simp: valid_tcb'_def obj_at'_def projectKOs inQ_def tcb_cte_cases_def)
                                apply (wpsimp wp: hoare_case_option_wp set_yf_sc_yf_sc_at[simplified op_equal])
                               apply (wpsimp wp:hoare_case_option_wp)
                               apply (wpsimp wp: set_sc'.obj_at' set_sc'.set_wp)
                              apply (wpsimp wp: syt_bound_tcb_at')
                             apply (clarsimp cong: conj_cong)
                             apply (wpsimp wp: threadSet_valid_queues threadSet_valid_queues'
                                               threadSet_vrq'_inv threadSet_vrq_inv threadSet_cur
                                               threadSet_valid_objs' hoare_drop_imp
                                         simp: fun_upd_def[symmetric])
                            apply (clarsimp simp: tcb_relation_def)
                           apply (rule_tac
                                    Q="\<lambda>_. sc_at scp and
                                           valid_objs and
                                           pspace_aligned and
                                           pspace_distinct and
                                           weak_valid_sched_action and
                                           active_sc_valid_refills and
                                           (\<lambda>s. bound_yt_tcb_at ((=) None) (cur_thread s) s) and
                                           (\<lambda>s. sc_tcb_sc_at (\<lambda>sctcb. \<exists>t. sctcb = Some t \<and> t \<noteq> cur_thread s) scp s) and
                                           tcb_at ct_ptr and
                                           tcb_at tp and sc_tcb_sc_at ((=) (Some tp)) scp"
                                  in hoare_strengthen_post)
                            apply (wpsimp cong: conj_cong imp_cong wp: hoare_drop_imp hoare_vcg_conj_lift)
                           apply clarsimp
                          apply (rule_tac Q="\<lambda>_. valid_objs' and cur_tcb'
                                                 and (\<lambda>s. scTCBs_of s scp = Some tp)
                                                 and ko_at' sc0' scp and tcb_at' ct_ptr
                                                 and valid_release_queue_iff and valid_queues and valid_queues'"
                                 in hoare_strengthen_post)
                           apply (wpsimp wp: setSchedContext_scTCBs_of)
                          apply (clarsimp simp: projectKOs opt_map_red)
                          apply (frule (1) sc_ko_at_valid_objs_valid_sc'[rotated])
                          apply (clarsimp simp: valid_sched_context'_def valid_sched_context_size'_def
                                                obj_at'_def projectKOs)
                          apply (erule_tac x=tp in valid_objsE', simp)
                          apply (fastforce simp: valid_obj'_def valid_tcb'_def obj_at'_def projectKOs
                                                 inQ_def tcb_cte_cases_def objBits_simps' scBits_simps)
                         apply (clarsimp simp: tcb_relation_def)
                        apply (wpsimp wp: hoare_vcg_if_lift2 hoare_drop_imp)
                       apply (wpsimp wp: hoare_vcg_if_lift2 hoare_drop_imp)
                      apply wpsimp
                     apply wpsimp
                    apply (rule_tac P="?abs_buf and sc_yf_sc_at ((=) None) scp and ?scp
                                       and (\<lambda>s. sched = schedulable tp s)"
                                and P'="?con_buf and cur_tcb' and ko_at' sc0' scp"
                           in corres_inst)
                    apply simp
                   apply (intro conjI impI; clarsimp cong: conj_cong)
                   apply (clarsimp simp: invs_def valid_state_def valid_pspace_def valid_sched_def
                                         valid_sched_action_weak_valid_sched_action pred_tcb_at_def
                                         sc_tcb_sc_at_def obj_at_def is_tcb is_sc_obj)
                   apply (fastforce simp: obj_at_def elim!: valid_sched_context_size_objsI)
                  apply (clarsimp cong: conj_cong simp: invs'_def valid_pspace'_def cur_tcb'_def)
                 apply (clarsimp simp:obj_at'_def projectKOs)
                 apply (wpsimp wp: thread_get_wp hoare_case_option_wp)+
                   apply (wpsimp wp: threadGet_wp)+
               apply (wpsimp wp: is_schedulable_wp)
              apply (wpsimp wp: isSchedulable_wp)
             apply (clarsimp simp: invs_def valid_state_def valid_pspace_def valid_objs_valid_tcbs
                             cong: conj_cong imp_cong if_cong)
             apply (rule context_conjI;
                    clarsimp simp: obj_at_def sc_tcb_sc_at_def is_sc_obj
                            elim!: valid_sched_context_size_objsI dest!: invs_valid_objs)
              apply (fastforce simp: valid_obj_def obj_at_def valid_sched_context_def)
             apply (intro conjI impI; clarsimp simp: is_tcb pred_tcb_at_def obj_at_def)
              apply (erule (1) valid_sched_context_size_objsI)+
            apply (clarsimp simp: invs'_def valid_pspace'_def valid_objs'_valid_tcbs')
            apply (clarsimp simp: obj_at'_def projectKOs opt_map_red)
           apply (rule_tac Q="\<lambda>rv. (case buf of None \<Rightarrow> \<lambda>_. True | Some x \<Rightarrow> in_user_frame x) and
                                   einvs and sc_yf_sc_at ((=) None) scp and
                                   (\<lambda>s. bound_yt_tcb_at ((=) None) (cur_thread s) s \<and>
                                        sc_tcb_sc_at (\<lambda>sctcb. \<exists>t. sctcb = Some t \<and> t \<noteq> cur_thread s) scp s)"
                  in hoare_strengthen_post[rotated])
            apply (fastforce simp: sc_tcb_sc_at_def obj_at_def is_sc_obj
                            elim!: valid_sched_context_size_objsI[OF invs_valid_objs])
           apply (wpsimp wp: hoare_case_option_wp sched_context_resume_valid_sched)
           apply ((wpsimp | wps)+)[1]
          apply (rule_tac Q="\<lambda>rv'. (case buf of None \<Rightarrow> \<lambda>_. True | Some x \<Rightarrow> valid_ipc_buffer_ptr' x)
                                   and invs' and sc_at' scp and cur_tcb'"
                 in hoare_strengthen_post[rotated])
           apply clarsimp
          apply (wpsimp wp:hoare_case_option_wp)
         apply clarsimp
         apply (clarsimp simp: invs_def valid_state_def valid_pspace_def valid_sched_def)
         apply (fastforce simp: sc_tcb_sc_at_def obj_at_def)
        apply (clarsimp simp: invs'_def valid_pspace'_def obj_at'_def projectKOs)
       apply wpsimp
        apply (rule_tac Q="\<lambda>_ s. (case buf of None \<Rightarrow> \<lambda>_. True | Some x \<Rightarrow> in_user_frame x) s \<and>
                                 invs s \<and> valid_list s \<and> valid_sched s \<and>
                                 bound_yt_tcb_at ((=) None) (cur_thread s) s \<and>
                                 sc_tcb_sc_at (\<lambda>sctcb. \<exists>t. sctcb = Some t \<and> t \<noteq> cur_thread s) scp s"
               in hoare_strengthen_post[rotated])
         apply (clarsimp simp: sc_yf_sc_at_def obj_at_def)
        apply (wpsimp wp: hoare_case_option_wp complete_yield_to_invs)
        apply ((wpsimp wp: complete_yield_to_sc_tcb_sc_at | wps)+)
       apply (clarsimp split: if_split simp: sc_yf_sc_at_def obj_at_def)
      apply (wpsimp wp: hoare_case_option_wp schedContextCompleteYieldTo_invs')
     apply wpsimp+
   apply (fastforce simp: sc_tcb_sc_at_def obj_at_def is_sc_obj
                   elim!: valid_sched_context_size_objsI[OF invs_valid_objs])
  apply clarsimp
  done

crunches sched_context_unbind_ntfn, sched_context_unbind_all_tcbs
  for sc_at[wp]: "sc_at scp"
  (wp: crunch_wps)

crunches schedContextUnbindNtfn, schedContextUnbindAllTCBs
  for sc_at'[wp]: "sc_at' scp"
  (wp: crunch_wps)

lemma invokeSchedContext_corres:
  "sc_inv_rel sc_inv sc_inv' \<Longrightarrow>
   corres (=)
          (einvs and valid_sched_context_inv sc_inv and simple_sched_action
           and current_time_bounded)
          (invs' and sch_act_simple and valid_sc_inv' sc_inv')
          (invoke_sched_context sc_inv)
          (invokeSchedContext sc_inv')"
  apply (simp add: invoke_sched_context_def invokeSchedContext_def)
  apply (cases sc_inv; cases sc_inv'; clarsimp simp: cap_relation_def)
      apply (rule corres_rel_imp)
       apply (rule corres_guard_imp)
         apply (rule setConsumed_corres)
        apply (clarsimp simp: invs_def valid_state_def valid_pspace_def)
       apply clarsimp
      apply simp
     apply (clarsimp  split: cap.split capability.split; intro conjI impI allI; clarsimp)
      apply (rule corres_guard_imp)
        apply (rule corres_rel_imp)
         apply (rule schedContextBindTCB_corres, simp)
       apply (clarsimp simp: invs_def valid_state_def valid_pspace_def)
      apply clarsimp
     apply (rule corres_guard_imp)
       apply (rule corres_rel_imp)
        apply (rule schedContextBindNtfn_corres)
       apply simp
      apply clarsimp
     apply (clarsimp simp: obj_at'_def)
    apply (clarsimp  split: cap.split capability.split; intro conjI impI allI; clarsimp)
     apply (rule corres_guard_imp)
       apply (rule corres_rel_imp)
        apply (rule schedContextUnbindTCB_corres, simp)
      apply (clarsimp simp: sc_tcb_sc_at_def obj_at_def obj_at'_def)+
    apply (rule corres_guard_imp)
      apply (rule corres_rel_imp)
       apply (rule schedContextUnbindNtfn_corres, simp)
     apply (clarsimp simp: sc_ntfn_sc_at_def obj_at_def is_sc_obj)+
     apply (fastforce simp: valid_sched_context_size_objsI dest!: invs_valid_objs)
    apply simp
   apply (rule corres_guard_imp)
     apply (rule corres_rel_imp)
      apply (rule corres_split[OF schedContextUnbindAllTCBs_corres])
        apply (rule corres_split[OF schedContextUnbindNtfn_corres])
          apply (rule schedContextUnbindReply_corres)
         apply wpsimp+
    apply (fastforce dest!: ex_nonz_cap_to_not_idle_sc_ptr)
   apply wpsimp
   apply (frule invs_valid_global')
   apply (fastforce dest!: invs_valid_pspace' global'_sc_no_ex_cap)
  apply (rule corres_guard_imp)
    apply (rule corres_rel_imp)
     apply (rule schedContextYieldTo_corres)
    apply simp
   apply clarsimp
  apply clarsimp
  done

lemmas sc_relation_refillResetRR1 =
  sc_relation_updateRefillTl[where f="r_amount_update (\<lambda>_. 0)" and f'="rAmount_update (\<lambda>_. 0)"]

lemma sc_relation_refillResetRR2:
  "\<lbrakk>sc_relation sc n sc'; length (sc_refills sc) = 2; sc_refill_max sc = MIN_REFILLS;
    sc_valid_refills' sc'; 1 < scRefillCount sc'\<rbrakk>
    \<Longrightarrow> sc_relation
             (sc_refills_update
               (\<lambda>refills. r_amount_update (\<lambda>m. m + r_amount (hd (tl refills))) (hd refills) # tl refills)
               sc)
             n ((scRefills_update
                         (\<lambda>_. updateAt (scRefillHead sc') (scRefills sc')
                                (\<lambda>hd. rAmount_update (\<lambda>_. rAmount hd + rAmount (refillTl sc')) hd)))
                 sc')"
  apply (case_tac "sc_refills sc"; simp)
  apply (rename_tac ls; case_tac ls; clarsimp simp: MIN_REFILLS_def)
  apply (cases sc; simp add: sc_relation_def refills_map_def)
  apply (prop_tac "scRefillCount sc' = 2")
   apply (insert length_wrap_slice[of "scRefillCount sc'" "scRefillMax sc'" "scRefillHead sc'" "scRefills sc'"])
   apply (case_tac "scRefillHead sc'"; simp)
  apply (clarsimp simp: refill_map_def updateAt_def Let_def null_def)
  apply (clarsimp simp: wrap_slice_def)
  apply (intro conjI; clarsimp simp: updateAt_def Let_def null_def refill_map_def)
   apply (case_tac "scRefills sc'"; simp)
   apply (rename_tac list; case_tac list; simp add: refill_map_def refillTl_def refillTailIndex_def)
  apply (case_tac "scRefillHead sc'"; simp)
  apply (intro conjI; clarsimp)
  apply (case_tac "scRefills sc'"; simp)
  apply (rename_tac list; case_tac list; simp add: refill_map_def refillTl_def refillTailIndex_def)
  done

lemma sc_relation_refillResetRR:
  "\<lbrakk>sc_relation sc n sc'; length (sc_refills sc) = 2; sc_refill_max sc = MIN_REFILLS;
    sc_valid_refills' sc'; 1 < scRefillCount sc'\<rbrakk>
   \<Longrightarrow> sc_relation
             (sc_refills_update
               ((\<lambda>refills. butlast refills @ [last refills\<lparr>r_amount := 0\<rparr>]) \<circ>
                (\<lambda>refills. r_amount_update (\<lambda>m. m + r_amount (hd (tl refills))) (hd refills) # tl refills))
               sc)
             n (((\<lambda>sc. scRefills_update (\<lambda>_. updateAt (refillTailIndex sc) (scRefills sc) (rAmount_update (\<lambda>_. 0)))
                         sc) \<circ>
                 (\<lambda>sc. scRefills_update
                         (\<lambda>_. updateAt (scRefillHead sc) (scRefills sc)
                                (\<lambda>hd. rAmount_update (\<lambda>_. rAmount hd + rAmount (refillTl sc)) hd))
                         sc))
                 sc')"
  apply (drule sc_relation_refillResetRR2; fastforce?)
  by (drule sc_relation_refillResetRR1; clarsimp simp: refill_map_def)

lemma refillResetRR_corres:
  "corres dc (sc_at csc_ptr and is_active_sc csc_ptr
                  and round_robin csc_ptr and valid_refills csc_ptr)
             (valid_objs' and sc_at' csc_ptr)
             (refill_reset_rr csc_ptr) (refillResetRR csc_ptr)"
  (is "corres dc ?abs ?conc _ _")
  supply projection_rewrites[simp]
  apply (subst is_active_sc_rewrite)
  apply (subst valid_refills_rewrite)
  apply (rule_tac Q="is_active_sc' csc_ptr" in corres_cross_add_guard)
   apply (fastforce dest!: is_active_sc'_cross[OF state_relation_pspace_relation])
  apply (rule_tac Q="\<lambda>s'. ((\<lambda>sc'. scRefillCount sc' = 2) |< scs_of' s') csc_ptr"
         in corres_cross_add_guard)
   apply (clarsimp simp: obj_at'_def projectKOs round_robin2_def obj_at_def is_sc_obj
                         rr_valid_refills_def is_active_sc2_def is_active_sc'_def opt_map_red)
   apply (drule (1) pspace_relation_absD[where x=csc_ptr, OF _ state_relation_pspace_relation])
   apply (erule (1) valid_objsE')
   apply (clarsimp simp: sc_relation_def refills_map_def valid_sched_context'_def valid_obj'_def)
  apply (clarsimp simp: refill_reset_rr_def refillResetRR_def get_refills_def updateRefillTl_def
                        update_sched_context_decompose[symmetric, simplified] update_refill_tl_def)
  apply (rule corres_guard_imp)
    apply (rule monadic_rewrite_corres'[OF _ monadic_rewrite_sym[OF updateSchedContext_decompose[simplified]]])
    apply (rule updateSchedContext_corres_gen[where
                 P="(\<lambda>s. ((\<lambda>sc. length (sc_refills sc) = 2 \<and> sc_refill_max sc = MIN_REFILLS) |< scs_of2 s) csc_ptr)"
            and P'="valid_objs' and is_active_sc' csc_ptr and (\<lambda>s'. ((\<lambda>sc'. scRefillCount sc' = 2) |< scs_of' s') csc_ptr)"])
      apply (clarsimp, drule (2) state_relation_sc_relation)
      apply (clarsimp simp: is_sc_obj obj_at_simps is_active_sc'_def opt_map_red)
      apply (erule (1) valid_objsE', clarsimp simp: valid_obj'_def valid_sched_context'_def)
      apply (fastforce elim!: sc_relation_refillResetRR[simplified])
     apply (fastforce simp: obj_at_simps is_sc_obj opt_map_red
                     dest!: state_relation_sc_replies_relation_sc)
     apply (clarsimp simp: objBits_simps)+
   apply (clarsimp simp: round_robin2_def obj_at_def is_sc_obj rr_valid_refills_def opt_map_red)
  by (clarsimp simp: objBits_simps)

lemma refillNew_corres:
  "\<lbrakk>1 < max_refills; valid_refills_number' max_refills (min_sched_context_bits + n)\<rbrakk>
   \<Longrightarrow> corres dc
         (pspace_aligned and pspace_distinct and sc_obj_at n sc_ptr) \<top>
            (refill_new sc_ptr max_refills budget period)
            (refillNew sc_ptr max_refills budget period)"
  supply projection_rewrites[simp]
  supply getSchedContext_wp[wp del] set_sc'.get_wp[wp del]
  apply (rule corres_cross_add_guard[where
      Q = "sc_at' sc_ptr and (\<lambda>s'. ((\<lambda>sc. objBits sc = minSchedContextBits + n) |< scs_of' s') sc_ptr)"])
   apply (fastforce dest!: sc_obj_at_cross[OF state_relation_pspace_relation]
                     simp: obj_at'_def projectKOs opt_map_red)
  apply (unfold refillNew_def refill_new_def setRefillHd_def updateRefillHd_def)
  apply (rule corres_guard_imp)
    apply (rule corres_split_eqr[OF _ getCurTime_corres])
      (* period *)
      apply (rule corres_split[OF updateSchedContext_corres]; clarsimp simp: objBits_simps)
     apply (fastforce simp: obj_at_simps is_sc_obj sc_relation_def opt_map_red
                     dest!: state_relation_sc_relation)
     apply (fastforce simp: obj_at_simps is_sc_obj opt_map_red
                     dest!: state_relation_sc_replies_relation_sc)
        (* budget *)
        apply (rule corres_split[OF updateSchedContext_corres]; (clarsimp simp: objBits_simps)?)
     apply (fastforce simp: obj_at_simps is_sc_obj sc_relation_def opt_map_red
                     dest!: state_relation_sc_relation)
           apply (fastforce simp: obj_at_simps is_sc_obj opt_map_red
                           dest!: state_relation_sc_replies_relation_sc)
          (* max_refills, sc_refills update *)
          (* rewrite into one step updateSchedContext corres *)
          apply (rename_tac ctime)
          apply (rule_tac P="sc_obj_at n sc_ptr and (\<lambda>s. ctime = cur_time s)"
                      and P'="sc_at' sc_ptr and (\<lambda>s'. ctime = ksCurTime s')
                              and (\<lambda>s'. ((\<lambda>sc'. objBits sc' = minSchedContextBits + n) |< scs_of' s') sc_ptr)"
                 in corres_inst)
          apply (subst bind_assoc[symmetric])
          apply (subst update_sched_context_decompose[symmetric, simplified])
          apply (subst bind_assoc[symmetric])
          apply (subst bind_assoc[symmetric])
          apply (subst bind_assoc)
          apply (rule corres_guard_imp)
            apply (rule corres_split[OF  monadic_rewrite_corres'
                                           [OF _ monadic_rewrite_sym
                                                   [OF updateSchedContext_decompose_x2[simplified]]]])
                  (* use setSchedContext_corres *)
                  apply (rule monadic_rewrite_corres[OF _ update_sched_context_rewrite[where n=n]])
                  apply (simp add: updateSchedContext_def)
                  apply (rule corres_split[OF get_sc_corres])
                    apply (rename_tac sc')
                    apply (rule_tac P="ko_at (kernel_object.SchedContext sc n) sc_ptr"
                                and P'="ko_at' sc' sc_ptr
                                        and (\<lambda>s'. ((\<lambda>sc'. objBits sc' = minSchedContextBits + n) |< scs_of' s') sc_ptr)"
                           in corres_inst)
                    apply (rule_tac F="length (scRefills sc') = max_num_refills (min_sched_context_bits + n)"
                           in corres_req)
                     apply (clarsimp simp: obj_at_simps scBits_simps opt_map_red)
                    using scBits_inverse_sc apply fastforce
                    apply (rule stronger_corres_guard_imp)
                      apply (rule_tac sc'="sc'\<lparr> scRefillMax := max_refills,
                                                scRefillHead := 0,
                                                scRefillCount := Suc 0,
                                                scRefills := updateAt 0 (scRefills sc') (\<lambda>r. Refill ctime budget)\<rparr>"
                             in setSchedContext_corres)
                       apply (clarsimp simp: sc_relation_def refills_map_def valid_refills_number'_def
                                             wrap_slice_start_0 max_num_refills_eq_refillAbsoluteMax')
                       apply (case_tac "scRefills sc'"; simp add: updateAt_def null_def refill_map_def)
                      apply (clarsimp simp: objBits_simps scBits_simps)
                     apply simp
                    apply (fastforce simp: obj_at_simps is_sc_obj opt_map_red
                                    dest!: sc_replies_relation_prevs_list[OF state_relation_sc_replies_relation])
                   apply (wpsimp wp: getSchedContext_wp')+
                 apply (clarsimp simp: objBits_simps)+
              (* last step : add tail *)
              apply (rule_tac P="sc_obj_at n sc_ptr and is_active_sc2 sc_ptr"
                          and P'="sc_at' sc_ptr
                                  and (\<lambda>s'. ((\<lambda>sc'. objBits sc' = minSchedContextBits + n
                                             \<and> scRefillHead sc' = 0 \<and> scRefillCount sc' = 1
                                             \<and> scRefillMax sc' = max_refills) |< scs_of' s') sc_ptr)"
                     in corres_inst)
              apply (rule stronger_corres_guard_imp)
                apply (rule maybeAddEmptyTail_corres[simplified dc_def])
               apply simp
              apply (clarsimp simp: obj_at_simps is_sc_obj scBits_simps opt_map_red
                                    valid_refills_number'_def)
              apply (drule (1) pspace_relation_absD[OF _ state_relation_pspace_relation, rotated])
              using scBits_inverse_sc apply fastforce
             apply (wpsimp wp: update_sched_context_wp updateSchedContext_wp)+
           apply (clarsimp simp:  obj_at_def is_sc_obj is_active_sc2_def)
          apply (clarsimp simp: obj_at_simps fun_upd_def[symmetric] valid_objs'_def ps_clear_upd
                                opt_map_red)
         apply (wpsimp wp: update_sched_context_wp updateSchedContext_wp)+
   apply (clarsimp simp:  obj_at_def is_sc_obj is_active_sc2_def)
  apply (clarsimp simp: obj_at_simps fun_upd_def[symmetric] valid_objs'_def ps_clear_upd opt_map_red)
  done

lemma refillUpdate_corres:
  "\<lbrakk>1 < max_refills; valid_refills_number' max_refills (min_sched_context_bits + n)\<rbrakk>
   \<Longrightarrow> corres dc
              ((is_active_sc2 sc_ptr and sc_obj_at n sc_ptr) and (pspace_aligned and pspace_distinct))
              (valid_refills' sc_ptr)
              (refill_update sc_ptr period budget max_refills)
              (refillUpdate sc_ptr period budget max_refills)"
  (is "_ \<Longrightarrow> _ \<Longrightarrow> corres _ (?pred and _) ?conc _ _")
  supply getSchedContext_wp[wp del] set_sc'.get_wp[wp del] projection_rewrites[simp]
  apply (rule corres_cross_add_guard[where
      Q = "sc_at' sc_ptr and (\<lambda>s'. ((\<lambda>sc. objBits sc = minSchedContextBits + n) |< scs_of' s') sc_ptr)"])
   apply (fastforce dest!: sc_obj_at_cross[OF state_relation_pspace_relation]
                     simp: obj_at'_def projectKOs opt_map_red)
  apply (rule_tac Q="is_active_sc' sc_ptr" in corres_cross_add_guard)
   apply (rule is_active_sc'_cross, fastforce+)
  apply (rule corres_guard_imp)
    apply (rule_tac P="?pred" and P'="?conc and sc_at' sc_ptr" in corres_inst)
    apply (unfold refillUpdate_def refill_update_def)
    apply simp
    (* rewrite the refill list update steps into one step updateSchedContext corres *)
    apply (subst bind_assoc[where m="update_sched_context _ _", symmetric])
    apply (subst update_sched_context_decompose[symmetric, simplified])
    apply (subst bind_assoc[where m="updateSchedContext _ _", symmetric])
    apply (subst bind_assoc[where m="do _ \<leftarrow> updateSchedContext _ _; updateSchedContext _ _ od", symmetric])
    apply (subst bind_assoc[where m="do _ \<leftarrow> (do _ \<leftarrow> updateSchedContext _ _; updateSchedContext _ _ od);
                                     updateSchedContext _ _ od", symmetric])
    apply (subst bind_assoc[where m="updateSchedContext _ _"])
    apply (subst bind_assoc[where m="updateSchedContext _ _"])
    apply (subst bind_assoc[where m="updateSchedContext _ _"])
    apply (rule stronger_corres_guard_imp)
      apply (rule corres_split[OF  monadic_rewrite_corres'
                                     [OF _ monadic_rewrite_sym
                                             [OF updateSchedContext_decompose_x3[simplified]]]])
                                       (* now use setSchedContext_corres *)
             apply (rule corres_inst[where P="?pred and sc_obj_at n sc_ptr" and P'="?conc and sc_at' sc_ptr"])
             (* one of the sc_obj_at n sc_ptr will be consumed by the next line *)
             apply (rule monadic_rewrite_corres[OF _ update_sched_context_rewrite[where n=n]])
             apply (simp add: updateSchedContext_def)
             apply (rule stronger_corres_guard_imp)
               apply (rule corres_split[OF get_sc_corres])
                 apply (rename_tac sc sc')
                 apply (rule_tac P="?pred and ko_at (kernel_object.SchedContext sc n) sc_ptr"
                             and P'="ko_at' sc' sc_ptr
                                     and K (objBits sc' = minSchedContextBits + n
                                                \<and> 0 < scRefillMax sc' \<and> sc_valid_refills' sc')"
                        in corres_inst)
                apply (rule_tac F="0 < scRefillMax sc' \<and> sc_valid_refills' sc'
                                    \<and> length (scRefills sc') = max_num_refills (min_sched_context_bits + n)"
                        in corres_req)
                  apply clarsimp
                  apply (clarsimp simp: obj_at'_def projectKOs objBits_simps scBits_simps)
                 using scBits_inverse_sc apply fastforce
                 apply (rule stronger_corres_guard_imp)
                   apply (rule setSchedContext_corres)
                    apply (unfold sc_relation_def; elim conjE exE; intro conjI; fastforce?)
                    apply (clarsimp simp: refills_map_def wrap_slice_start_0 hd_map neq_Nil_lengthI
                                          refill_map_def updateAt_def null_def refillHd_def hd_wrap_slice
                                          valid_refills_number'_def max_num_refills_eq_refillAbsoluteMax')
                   apply (clarsimp simp: objBits_simps scBits_simps)
                  apply simp
                 apply (clarsimp simp: obj_at_simps scBits_simps is_sc_obj)
                 apply (fastforce elim!: sc_replies_relation_prevs_list[OF state_relation_sc_replies_relation])
                apply wpsimp
               apply (wpsimp wp: getSchedContext_wp')
              apply (clarsimp simp: obj_at_def is_sc_obj)
             apply (drule state_relation_sc_relation[where ptr=sc_ptr];
                   (fastforce simp: obj_at_simps is_sc_obj obj_bits_def)?)
             apply (clarsimp simp: obj_at_simps is_sc_obj valid_refills_number'_def scBits_simps
                                   opt_map_red valid_refills'_def
                            dest!: scRefills_length)
            apply ((clarsimp simp: objBits_simps)+)[2]
        (* sc_period *)
        apply (rule corres_split[OF updateSchedContext_corres])
             apply (fastforce dest!: state_relation_sc_relation
                               simp: obj_at_simps is_sc_obj sc_relation_def opt_map_red)
            apply (fastforce dest!: state_relation_sc_replies_relation_sc
                              simp: obj_at_simps is_sc_obj sc_relation_def opt_map_red)
           apply (simp add: objBits_simps)
          (* sc_budget *)
          apply (rule corres_split[OF updateSchedContext_corres])
               apply (fastforce dest!: state_relation_sc_relation
                                 simp: obj_at_simps is_sc_obj sc_relation_def opt_map_red)
              apply (fastforce dest!: state_relation_sc_replies_relation_sc
                                simp: obj_at_simps is_sc_obj sc_relation_def opt_map_red)
             apply (simp add: objBits_simps)
            (* the rest *)
            apply (rule_tac P="sc_obj_at n sc_ptr and
                              (\<lambda>s. ((\<lambda>sc. sc_refills sc\<noteq> [] \<and> 0 < sc_refill_max sc) |< scs_of s) sc_ptr)"
                       and P'="sc_at' sc_ptr and
                              (\<lambda>s'. ((\<lambda>ko. 1 < scRefillMax ko \<and> scRefillCount ko = 1 \<and> sc_valid_refills' ko)
                                            |< scs_of' s') sc_ptr)"
                   in corres_inst)
            apply (simp add: when_def[symmetric] whenM_def ifM_def bind_assoc split del: if_split)
            apply (rule corres_guard_imp)
              apply (rule corres_split[OF refillReady_corres]) (* projection version *)
                (* when-block *)
                apply (rule corres_split[OF corres_when], simp)
                   apply (rule corres_split[OF getCurTime_corres])
                     apply (rule corres_guard_imp)
                       apply (rule updateRefillHd_corres, simp)
                       apply (simp add: refill_map_def)
                      apply (simp+)[2]
                    apply (wpsimp+)[2]
                  apply (simp add: liftM_def bind_assoc)
                  apply (rule corres_split[OF get_sc_corres])
                    (* if-block *)
                    apply (rename_tac sc sc')
                    apply (rule_tac P="ko_at (kernel_object.SchedContext sc n) sc_ptr
                                       and K (0 < sc_refill_max sc) and K (sc_refills sc \<noteq> [])
                                        and K (valid_sched_context_size n)"
                                and P'="ko_at' sc' sc_ptr
                                        and K (1 < scRefillMax sc' \<and> scRefillCount sc' = 1 \<and> sc_valid_refills' sc')"
                           in corres_inst)
                    apply (rule_tac F="refill_hd sc = refill_map (refillHd sc')" in corres_req)
                     apply (fastforce dest!: refill_hd_relation)
                    apply (rule corres_guard_imp)
                      apply (rule corres_if)
                        apply (clarsimp simp: refill_map_def)
                       apply (rule corres_split[OF updateRefillHd_corres], simp)
                          apply (clarsimp simp: refill_map_def)
                         apply (rule maybeAddEmptyTail_corres)
                        apply (wpsimp simp: update_refill_hd_rewrite)
                       apply (wpsimp simp: updateRefillHd_def wp: updateSchedContext_wp)
                      apply (rule refillAddTail_corres)
                      apply (clarsimp simp: refill_map_def)
                     apply (clarsimp simp: obj_at_def is_sc_obj is_active_sc2_def opt_map_red)
                    apply (clarsimp simp: obj_at_simps opt_map_red is_sc_obj ps_clear_upd
                                          scBits_simps fun_upd_def[symmetric] valid_refills'_def)
                   apply wpsimp
                  apply (wpsimp wp: getSchedContext_wp')
                 apply (wpsimp simp: update_refill_hd_def wp: update_sched_context_wp)
                apply (wpsimp simp: updateRefillHd_def objBits_simps
                                wp: updateSchedContext_wp)
               apply (wpsimp wp: get_sc_refill_ready_wp)
              apply (wpsimp wp: refillReady_wp')
             apply (fastforce simp: obj_at_def is_sc_obj is_active_sc2_def opt_map_red)
            apply (fastforce simp: obj_at_simps ps_clear_upd fun_upd_def[symmetric]
                                   valid_refills'_def opt_map_red)
           apply ((wpsimp wp: updateSchedContext_wp update_sched_context_wp simp: objBits_simps)+)[5]
      apply (rule monadic_rewrite_refine_valid[where P''=\<top>, OF updateSchedContext_decompose_x3, simplified])
          apply ((clarsimp simp: objBits_simps)+)[2]
      apply (wpsimp wp: updateSchedContext_wp simp: objBits_simps)
     apply (clarsimp simp: obj_at_def is_sc_obj is_active_sc2_def opt_map_red)
    apply (clarsimp simp: obj_at_simps scBits_simps ps_clear_upd fun_upd_def[symmetric]
                          valid_refills_number'_def is_sc_obj)
    apply (drule (1) pspace_relation_absD[OF _ state_relation_pspace_relation])
    apply (fastforce simp: valid_sched_context'_def valid_obj'_def valid_refills_number'_def
                           valid_sched_context_size'_def scBits_simps objBits_simps opt_map_red
                    dest!: scRefills_length)
   apply clarsimp+
  done

crunches maybeAddEmptyTail, setRefillHd
  for invs'[wp]: invs'
  (simp: crunch_simps wp: crunch_wps)

lemma refillNew_invs':
  "\<lbrace>\<lambda>s. invs' s \<and> (\<exists>n. sc_at'_n n scPtr s \<and> valid_refills_number' maxRefills n)
        \<and> ex_nonz_cap_to' scPtr s \<and> MIN_REFILLS \<le> maxRefills\<rbrace>
   refillNew scPtr maxRefills budget period
   \<lbrace>\<lambda>_. invs'\<rbrace>"
  (is "\<lbrace>?P\<rbrace> _ \<lbrace>?Q\<rbrace>")
  apply (clarsimp simp: refillNew_def)
  apply (rule hoare_seq_ext_skip, wpsimp)

  apply (rule hoare_seq_ext_skip)
   apply (intro hoare_vcg_conj_lift_pre_fix; (solves wpsimp)?)
    apply (wpsimp wp: updateSchedContext_invs')
    apply (fastforce dest: invs'_ko_at_valid_sched_context'
                     simp: valid_sched_context'_def valid_sched_context_size'_def objBits_simps)
   apply (wpsimp wp: updateSchedContext_wp)
   apply (clarsimp simp: obj_at_simps ko_wp_at'_def ps_clear_def opt_map_def)

  apply (rule hoare_seq_ext_skip)
   apply (intro hoare_vcg_conj_lift_pre_fix; (solves wpsimp)?)
    apply (wpsimp wp: updateSchedContext_invs')
    apply (fastforce dest: invs'_ko_at_valid_sched_context'
                     simp: valid_sched_context'_def valid_sched_context_size'_def objBits_simps)
   apply (wpsimp wp: updateSchedContext_wp)
   apply (clarsimp simp: obj_at_simps ko_wp_at'_def ps_clear_def opt_map_def)

  apply (simp flip: bind_assoc)
  apply (rule hoare_seq_ext)
   apply wpsimp
  apply (rule hoare_seq_ext)
   apply wpsimp

  apply (clarsimp simp: pred_conj_def)
  apply (intro hoare_vcg_conj_lift_pre_fix)
   apply (find_goal \<open>match conclusion in "\<lbrace>P\<rbrace> f \<lbrace>\<lambda>_. active_sc_at' scPtr\<rbrace>" for P f \<Rightarrow> -\<close>)
   apply (wpsimp wp: updateSchedContext_wp)
   apply (clarsimp simp: active_sc_at'_def obj_at_simps MIN_REFILLS_def ps_clear_def)
  apply (clarsimp simp: updateSchedContext_def bind_assoc)
  apply (subst bind_dummy_ret_val)+
  apply (rule hoare_weaken_pre)
   apply (rule_tac P'="?P" and P''="sc_at' scPtr" and Q="?Q"
                in monadic_rewrite_refine_valid[OF getSchedContext_setSchedContext_decompose];
          (solves wpsimp)?)
   apply (wpsimp wp: setSchedContext_invs')
   apply (fastforce dest: invs'_ko_at_valid_sched_context'
                    simp: valid_sched_context'_def valid_sched_context_size'_def obj_at_simps
                          ko_wp_at'_def valid_refills_number'_def)
  apply (clarsimp simp: obj_at_simps ko_wp_at'_def)
  apply (case_tac ko; clarsimp)
  done

lemma refillUpdate_invs':
  "\<lbrace>\<lambda>s. invs' s \<and> (\<exists>n. sc_at'_n n scPtr s \<and> valid_refills_number' newMaxRefills n)
        \<and> ex_nonz_cap_to' scPtr s \<and> MIN_REFILLS \<le> newMaxRefills\<rbrace>
   refillUpdate  scPtr newPeriod newBudget newMaxRefills
   \<lbrace>\<lambda>_. invs'\<rbrace>"
  (is "\<lbrace>?P\<rbrace> _ \<lbrace>_\<rbrace>")
  apply (clarsimp simp: refillUpdate_def)
  apply (simp flip: bind_assoc)
  apply (rule_tac B="\<lambda>_. invs' and active_sc_at' scPtr" in hoare_seq_ext)
   apply (wpsimp wp: updateRefillHd_invs')
  apply (clarsimp simp: pred_conj_def)
  apply (intro hoare_vcg_conj_lift_pre_fix)
   apply (find_goal \<open>match conclusion in "\<lbrace>P\<rbrace> f \<lbrace>\<lambda>_. active_sc_at' scPtr\<rbrace>" for P f \<Rightarrow> -\<close>)
   apply (wpsimp wp: updateSchedContext_wp refillReady_wp
               simp: updateRefillHd_def)
   apply (clarsimp simp: active_sc_at'_def obj_at_simps MIN_REFILLS_def ps_clear_def)
  apply (rule_tac B="\<lambda>_. invs'" in hoare_seq_ext)
   apply wpsimp
  apply (rule_tac B="\<lambda>_. invs' and active_sc_at' scPtr" in hoare_seq_ext)
   apply (wpsimp wp: updateRefillHd_invs' refillReady_wp)
  apply (clarsimp simp: pred_conj_def)
  apply (intro hoare_vcg_conj_lift_pre_fix)
   apply (find_goal \<open>match conclusion in "\<lbrace>P\<rbrace> f \<lbrace>\<lambda>_. active_sc_at' scPtr\<rbrace>" for P f \<Rightarrow> -\<close>)
   apply (wpsimp wp: updateSchedContext_wp refillReady_wp
               simp: updateRefillHd_def)
   apply (clarsimp simp: active_sc_at'_def obj_at_simps MIN_REFILLS_def ps_clear_def)
  apply (rule_tac B="\<lambda>_. invs' and ex_nonz_cap_to' scPtr" in hoare_seq_ext)
   apply (wpsimp wp: updateSchedContext_invs')
   apply (fastforce dest: invs'_ko_at_valid_sched_context'
                    simp: valid_sched_context'_def valid_sched_context_size'_def obj_at_simps)
  apply (clarsimp simp: pred_conj_def)
  apply (intro hoare_vcg_conj_lift_pre_fix)
   apply (find_goal \<open>match conclusion in "\<lbrace>P\<rbrace> f \<lbrace>\<lambda>_. ex_nonz_cap_to' scPtr\<rbrace>" for P f \<Rightarrow> -\<close>)
   apply (wpsimp wp: updateSchedContext_ex_nonz_cap_to' refillReady_wp
               simp: updateRefillHd_def)
  apply (rule_tac B="\<lambda>_. invs' and ex_nonz_cap_to' scPtr" in hoare_seq_ext)
   apply (wpsimp wp: updateSchedContext_invs')
   apply (fastforce dest: invs'_ko_at_valid_sched_context'
                    simp: valid_sched_context'_def valid_sched_context_size'_def obj_at_simps)
  apply (simp add: bind_assoc)
  apply (clarsimp simp: pred_conj_def)
  apply (intro hoare_vcg_conj_lift_pre_fix)
   apply (find_goal \<open>match conclusion in "\<lbrace>P\<rbrace> f \<lbrace>\<lambda>_. ex_nonz_cap_to' scPtr\<rbrace>" for P f \<Rightarrow> -\<close>)
   apply (wpsimp wp: updateSchedContext_ex_nonz_cap_to')

  apply (rule hoare_seq_ext_skip)
   apply (intro hoare_vcg_conj_lift_pre_fix; (solves wpsimp)?)
    apply (wpsimp wp: updateSchedContext_invs')
    apply (fastforce dest: invs'_ko_at_valid_sched_context'
                     simp: valid_sched_context'_def valid_sched_context_size'_def objBits_simps)
   apply (wpsimp wp: updateSchedContext_wp)
   apply (clarsimp simp: obj_at_simps ko_wp_at'_def ps_clear_def opt_map_def)
  apply (rule_tac B="\<lambda>_. ?P and (\<lambda>s'. ((\<lambda>sc'. scRefillHead sc' = 0) |< scs_of' s') scPtr)"
               in hoare_seq_ext[rotated])
   apply (clarsimp simp: pred_conj_def)
   apply (intro hoare_vcg_conj_lift_pre_fix; (solves wpsimp)?)
     apply (wpsimp wp: updateSchedContext_invs')
     apply (fastforce dest: invs'_ko_at_valid_sched_context'
                      simp: valid_sched_context'_def valid_sched_context_size'_def objBits_simps)
    apply (wpsimp wp: updateSchedContext_wp)
    apply (clarsimp simp: obj_at_simps ko_wp_at'_def ps_clear_def opt_map_def)
   apply (wpsimp wp: updateSchedContext_wp)
  apply (rule_tac B="\<lambda>_. ?P and (\<lambda>s'. ((\<lambda>sc'. scRefillHead sc' = 0) |< scs_of' s') scPtr)
                            and (\<lambda>s'. ((\<lambda>sc'. scRefillCount sc' = 1) |< scs_of' s') scPtr)"
               in hoare_seq_ext[rotated])
   apply (clarsimp simp: pred_conj_def)
   apply (intro hoare_vcg_conj_lift_pre_fix; (solves wpsimp)?)
      apply (wpsimp wp: updateSchedContext_invs')
      apply (fastforce dest: invs'_ko_at_valid_sched_context'
                     simp: valid_sched_context'_def valid_sched_context_size'_def objBits_simps)
     apply (wpsimp wp: updateSchedContext_wp)
     apply (clarsimp simp: obj_at_simps ko_wp_at'_def ps_clear_def opt_map_def)
    apply (wpsimp wp: updateSchedContext_wp)
    apply (clarsimp simp: obj_at_simps ko_wp_at'_def ps_clear_def opt_map_def)
   apply (wpsimp wp: updateSchedContext_wp)
  apply (wpsimp wp: updateSchedContext_invs')
  apply (fastforce dest: invs'_ko_at_valid_sched_context'
                   simp: valid_sched_context'_def valid_sched_context_size'_def obj_at_simps
                         ko_wp_at'_def valid_refills_number'_def opt_map_red)
  done

lemma tcbSchedDequeue_valid_refills'[wp]:
  "tcbSchedDequeue tcbPtr \<lbrace>valid_refills' scPtr\<rbrace>"
  apply (clarsimp simp: tcbSchedDequeue_def)
  apply (wpsimp wp: threadSet_wp threadGet_wp
              simp: bitmap_fun_defs setQueue_def
         | intro conjI impI)+
  apply (fastforce simp: obj_at_simps valid_refills'_def opt_map_def split: option.splits)
  done

crunches tcbSchedDequeue, tcbReleaseRemove
  for ksCurSc[wp]: "\<lambda>s. P (ksCurSc s)"
  (wp: crunch_wps threadSet_wp simp: setQueue_def valid_refills'_def bitmap_fun_defs crunch_simps)

lemma tcbReleaseRemove_valid_refills'[wp]:
  "tcbReleaseRemove tcbPtr \<lbrace>valid_refills' scPtr\<rbrace>"
  apply (clarsimp simp: tcbReleaseRemove_def)
  apply (wpsimp wp: threadSet_wp threadGet_wp
              simp: bitmap_fun_defs setReleaseQueue_def setReprogramTimer_def
         | intro conjI impI)+
    apply (fastforce simp: obj_at_simps valid_refills'_def opt_map_def split: option.splits)+
  done

crunches commitTime, refillNew, refillUpdate
  for ksCurSc[wp]: "\<lambda>s. P (ksCurSc s)"
  (wp: crunch_wps simp: crunch_simps)

crunches commitTime
  for ex_nonz_cap_to'[wp]: "ex_nonz_cap_to' ptr"
  (wp: crunch_wps simp: crunch_simps)

lemma invokeSchedControlConfigureFlags_corres:
  "sc_ctrl_inv_rel sc_inv sc_inv' \<Longrightarrow>
   corres dc
          (einvs and valid_sched_control_inv sc_inv and cur_sc_active and schact_is_rct
           and ct_not_in_release_q and ct_active
           and current_time_bounded and consumed_time_bounded
           and (\<lambda>s. cur_sc_offset_ready (consumed_time s) s)
           and (\<lambda>s. cur_sc_offset_sufficient (consumed_time s) s))
          (invs' and sch_act_simple and valid_sc_ctrl_inv' sc_inv' and ct_active')
          (invoke_sched_control_configure_flags sc_inv)
          (invokeSchedControlConfigureFlags sc_inv')"
  (is "_ \<Longrightarrow> corres _ ?abs ?conc _ _")
  apply (cases sc_inv)
  apply (rename_tac sc_ptr budget period mrefills badge flag)
  apply (simp add: invoke_sched_control_configure_flags_def invokeSchedControlConfigureFlags_def)
  apply (subst bind_dummy_ret_val)+

  apply (rule_tac Q="\<lambda>s. sc_at sc_ptr s" in corres_cross_add_abs_guard)
   apply (fastforce intro: valid_sched_context_size_objsI
                     simp: sc_at_pred_n_def obj_at_def is_sc_obj_def)
  apply (rule_tac Q="\<lambda>s'. sc_at' sc_ptr s'" in corres_cross_add_guard)
   apply (fastforce intro: sc_at_cross)
  apply (rule_tac Q="\<lambda>s. sc_at (cur_sc s) s" in corres_cross_add_abs_guard)
   apply (fastforce intro: cur_sc_tcb_sc_at_cur_sc)
  apply (rule_tac Q="\<lambda>s'. active_sc_at' (ksCurSc s') s'" in corres_cross_add_guard)
   apply (fastforce intro: active_sc_at'_cross simp: state_relation_def)

  apply (rule_tac Q="\<lambda>_ s. ?abs s \<and> sc_at sc_ptr s \<and> sc_at (cur_sc s) s"
              and Q'="\<lambda>_  s'. ?conc s' \<and> ex_nonz_cap_to' sc_ptr s' \<and> sc_at' sc_ptr s'
                              \<and> active_sc_at' (ksCurSc s') s'"
               in corres_split')

     apply (find_goal \<open>match conclusion in "\<lbrace>P\<rbrace> f \<lbrace>Q\<rbrace>" for P f Q  \<Rightarrow> -\<close>)
     apply wps_conj_solves
      apply (wpsimp wp: update_sc_badge_invs')
      apply (fastforce dest: ex_nonz_cap_to_not_idle_sc_ptr)
     apply (wpsimp wp: update_sched_context_wp)
     apply (clarsimp simp: obj_at_def)

    apply (find_goal \<open>match conclusion in "\<lbrace>P\<rbrace> f \<lbrace>Q\<rbrace>" for P f Q  \<Rightarrow> -\<close>)
    apply (wps_conj_solves wp: ct_in_state_thread_state_lift' updateSchedContext_active_sc_at')
     apply (clarsimp simp: updateSchedContext_def)
     apply (wpsimp wp: setSchedContext_invs')
     apply (fastforce dest!: sc_ko_at_valid_objs_valid_sc')

   apply (corressimp corres: updateSchedContext_corres)
   apply (intro conjI impI allI)
     apply (rename_tac abs_state conc_state n')
     apply (frule_tac ptr=sc_ptr and s=abs_state in state_relation_sc_relation; simp?)
     apply (clarsimp simp: sc_relation_def opt_map_def is_sc_obj_def obj_at_simps
                    split: Structures_A.kernel_object.splits)
    apply (rename_tac abs_state conc_state)
    apply (frule_tac s=abs_state in state_relation_sc_replies_relation)
    apply (clarsimp simp: sc_replies_relation2_def sc_replies_relation_rewrite)
    apply (fastforce simp: opt_map_def is_sc_obj_def obj_at_simps
                    split: option.splits Structures_A.kernel_object.splits)
   apply (clarsimp simp: obj_at_simps)

  apply (clarsimp split del: if_split)
  apply (rule_tac Q="\<lambda>_ s. sc_at sc_ptr s \<and> ?abs s \<and> sc_at (cur_sc s) s"
              and Q'="\<lambda>_  s'. ?conc s' \<and> sc_at' sc_ptr s' \<and> active_sc_at' (ksCurSc s') s'
                              \<and> ex_nonz_cap_to' sc_ptr s'"
               in corres_split')

     apply (find_goal \<open>match conclusion in "\<lbrace>P\<rbrace> f \<lbrace>Q\<rbrace>" for P f Q  \<Rightarrow> -\<close>)
     apply wps_conj_solves
      apply (wpsimp wp: update_sc_sporadic_invs')
      apply (fastforce dest: ex_nonz_cap_to_not_idle_sc_ptr)
     apply (wpsimp wp: update_sched_context_wp)
     apply (clarsimp simp: obj_at_def)

    apply (find_goal \<open>match conclusion in "\<lbrace>P\<rbrace> f \<lbrace>Q\<rbrace>" for P f Q  \<Rightarrow> -\<close>)
    apply (wps_conj_solves wp: ct_in_state_thread_state_lift' updateSchedContext_active_sc_at')
     apply (clarsimp simp: updateSchedContext_def)
     apply (wpsimp wp: setSchedContext_invs')
     apply (fastforce dest!: sc_ko_at_valid_objs_valid_sc')

   apply (corressimp corres: updateSchedContext_corres)
   apply (intro conjI impI allI)
     apply (rename_tac abs_state conc_state n')
     apply (frule_tac ptr=sc_ptr and s=abs_state in state_relation_sc_relation; simp?)
     apply (clarsimp simp: sc_relation_def opt_map_def is_sc_obj_def obj_at_simps
                    split: Structures_A.kernel_object.splits)
    apply (rename_tac abs_state conc_state)
    apply (frule_tac s=abs_state in state_relation_sc_replies_relation)
    apply (clarsimp simp: sc_replies_relation2_def sc_replies_relation_rewrite)
    apply (fastforce simp: opt_map_def is_sc_obj_def obj_at_simps
                    split: option.splits Structures_A.kernel_object.splits)
   apply (clarsimp simp: obj_at_simps)

  apply (rule_tac F="budget \<le> MAX_PERIOD \<and> budget \<ge> MIN_BUDGET \<and> period \<le> MAX_PERIOD
                     \<and> budget \<ge> MIN_BUDGET \<and> MIN_REFILLS \<le> mrefills \<and> budget \<le> period"
               in corres_req)
   apply simp

  apply (clarsimp simp: sc_at_sc_obj_at)
  apply (rule abs_ex_lift_corres)
  apply (rename_tac n)
  apply (rule corres_split'[rotated 2, OF get_sched_context_sp get_sc_sp'])
   apply (rule corres_guard_imp)
     apply (rule_tac n=n in get_sc_corres_size)
    apply fast
   apply fast

  apply (rule_tac F="valid_refills_number' mrefills (min_sched_context_bits + n)" in corres_req)
   apply (clarsimp simp: obj_at_simps valid_refills_number'_def ko_wp_at'_def  sc_const_eq)
   apply (rule_tac y="refillAbsoluteMax' (scBitsFromRefillLength' (length (scRefills obj)))"
                in order_trans)
    apply fastforce
   apply (fastforce intro: refillAbsoluteMax'_mono
                     simp: sc_const_eq)

  apply (rename_tac sc')
  apply (rule_tac Q="\<lambda>_ s. invs s \<and> schact_is_rct s \<and> current_time_bounded s
                           \<and> valid_sched_action s \<and> active_sc_valid_refills s
                           \<and> valid_ready_qs s \<and> valid_release_q s
                           \<and> sc_at (cur_sc s) s
                           \<and> sc_not_in_release_q sc_ptr s \<and> sc_not_in_ready_q sc_ptr s
                           \<and> sc_ptr \<noteq> idle_sc_ptr \<and> sc_at sc_ptr s
                           \<and> sc_refill_max_sc_at (\<lambda>rm. rm = sc_refill_max sc) sc_ptr s
                           \<and> sc_tcb_sc_at (\<lambda>to. to = sc_tcb sc) sc_ptr s
                           \<and> sc_obj_at n sc_ptr s
                           \<and> (\<forall>tcb_ptr. sc_tcb_sc_at ((=) (Some tcb_ptr)) sc_ptr s \<longrightarrow> tcb_at tcb_ptr s)"
              and Q'="\<lambda>_ s'. invs' s' \<and> sc_at' (ksCurSc s') s'
                             \<and> (\<exists>n. sc_at'_n n sc_ptr s' \<and> valid_refills_number' mrefills n)
                             \<and> ex_nonz_cap_to' sc_ptr s'"
              and r'=dc
               in corres_split')

     apply (clarsimp simp: when_def split del: if_split)
     apply (rule corres_if_split; (solves \<open>corressimp simp: sc_relation_def\<close>)?)
     apply (rule corres_symb_exec_l[rotated])
        apply (wpsimp wp: exs_valid_assert_opt)
       apply (rule assert_opt_sp)
      apply wpsimp
     apply (rule_tac F="scTCB sc' = Some tcb_ptr" in corres_req)
      apply (fastforce simp: sc_relation_def)
     apply (rule corres_guard_imp)
       apply (rule corres_split[OF tcbReleaseRemove_corres])
          apply (clarsimp simp: sc_relation_def)
         apply clarsimp
         apply (rule corres_split[OF tcbSchedDequeue_corres])
           apply (rule corres_split[OF getCurSc_corres])
             apply clarsimp
             apply (simp add: dc_def[symmetric])
             apply (rule commitTime_corres)
            apply (wpsimp wp: hoare_drop_imps tcbReleaseRemove_valid_queues | wps)+
      apply (intro conjI impI; fastforce?)
       apply (fastforce dest: invs_valid_objs valid_sched_context_objsI
                        simp: valid_sched_context_def valid_bound_obj_def obj_at_def)
      apply (fastforce intro: active_sc_valid_refillsE)
     apply (fastforce dest: invs_valid_objs' sc_ko_at_valid_objs_valid_sc'
                     intro: valid_objs'_valid_refills'
                      simp: valid_sched_context'_def valid_bound_obj'_def active_sc_at'_rewrite)

    apply (find_goal \<open>match conclusion in "\<lbrace>P\<rbrace> f \<lbrace>Q\<rbrace>" for P f Q  \<Rightarrow> -\<close>)
    apply wps_conj_solves
            apply (wpsimp wp: commit_time_invs)
           apply (wpsimp wp: commit_time_valid_sched_action hoare_vcg_imp_lift')
           apply fastforce
          apply (wpsimp wp: commit_time_active_sc_valid_refills
                            hoare_vcg_imp_lift')
          apply (fastforce intro: cur_sc_active_offset_ready_and_sufficient_implies_cur_sc_more_than_ready)
         apply (wpsimp wp: commit_time_valid_ready_qs hoare_vcg_imp_lift'
                           tcb_sched_dequeue_valid_ready_qs hoare_vcg_disj_lift)
         apply (fastforce intro: cur_sc_active_offset_ready_and_sufficient_implies_cur_sc_more_than_ready)
        apply (wpsimp wp: commit_time_valid_release_q hoare_vcg_imp_lift'
                          tcb_release_remove_cur_sc_in_release_q_imp_zero_consumed'
               | strengthen invs_valid_stateI)+
        apply (frule cur_sc_tcb_are_bound_cur_sc_in_release_q_imp_zero_consumed[rotated 2])
          apply (fastforce intro: invs_strengthen_cur_sc_tcb_are_bound)
         apply fastforce
        apply (fastforce simp: cur_sc_in_release_q_imp_zero_consumed_2_def)
       apply (wpsimp wp: tcb_release_remove_sc_not_in_release_q)
       apply (intro conjI impI; fastforce?)
        apply (rule disjI2)
        apply (intro conjI)
         apply (fastforce dest!: invs_sym_refs sym_ref_sc_tcb
                           simp: heap_refs_inv_def vs_all_heap_simps obj_at_def sc_at_pred_n_def)
        apply (fastforce intro: sym_refs_inj_tcb_scps)
       apply (drule valid_sched_valid_release_q)
       apply (clarsimp simp: vs_all_heap_simps)
       apply (frule_tac ref=t in valid_release_q_no_sc_not_in_release_q)
        apply (fastforce dest!: invs_sym_refs sym_ref_tcb_sc
                          simp: obj_at_def vs_all_heap_simps is_sc_obj_def)
       apply fastforce
      apply (wpsimp wp: tcb_sched_dequeue_sc_not_in_ready_q)

       apply (intro conjI impI; fastforce?)
         apply (fastforce dest!: invs_sym_refs sym_ref_sc_tcb
                           simp: heap_refs_inv_def vs_all_heap_simps obj_at_def sc_at_pred_n_def)
        apply (fastforce intro: sym_refs_inj_tcb_scps)
       apply (frule invs_valid_objs)
       apply (frule_tac r=sc_ptr in valid_sched_context_objsI)
        apply (fastforce simp: obj_at_def)
       apply (clarsimp simp: valid_sched_context_def)
       apply (drule valid_sched_valid_ready_qs)
       apply (clarsimp simp: vs_all_heap_simps)
       apply (frule_tac ref=t in valid_ready_qs_no_sc_not_queued)
        apply (fastforce dest!: invs_sym_refs sym_ref_tcb_sc
                          simp: obj_at_def vs_all_heap_simps is_sc_obj_def)
       apply fastforce
     apply wpsimp
     using idle_sc_no_ex_cap apply fastforce
    apply wpsimp
    apply (clarsimp simp: sc_at_pred_n_def obj_at_def)

     apply (rule hoare_when_cases, simp)
      apply (clarsimp simp: sc_at_pred_n_def obj_at_def)
     apply (rule_tac Q="sc_tcb_sc_at (\<lambda>to. to = sc_tcb sc) sc_ptr" in hoare_weaken_pre[rotated])
      apply (clarsimp simp: sc_at_pred_n_def obj_at_def)
     apply (rule hoare_seq_ext_skip, wpsimp)+
     apply wpsimp

    apply (wpsimp wp: hoare_vcg_all_lift hoare_vcg_imp_lift')
    apply (fastforce dest: invs_valid_objs valid_sched_context_objsI
                     simp: valid_sched_context_def valid_bound_obj_def sc_at_pred_n_def obj_at_def
                    split: option.splits)

   apply (find_goal \<open>match conclusion in "\<lbrace>P\<rbrace> f \<lbrace>Q\<rbrace>" for P f Q  \<Rightarrow> -\<close>)
   apply (wps_conj_solves wp: commitTime_invs' tcbReleaseRemove_invs'
                        simp: active_sc_at'_rewrite)

  apply (rule_tac Q="\<lambda>_ s. invs s \<and> schact_is_rct s \<and> current_time_bounded s
                           \<and> valid_sched_action s \<and> active_sc_valid_refills s
                           \<and> valid_ready_qs s \<and> valid_release_q s
                           \<and> sc_at (cur_sc s) s
                           \<and> sc_at sc_ptr s
                           \<and> sc_tcb_sc_at (\<lambda>to. to = sc_tcb sc) sc_ptr s
                           \<and> (\<forall>tcb_ptr. sc_tcb_sc_at ((=) (Some tcb_ptr)) sc_ptr s \<longrightarrow> tcb_at tcb_ptr s)"
              and Q'="\<lambda>_ s'. invs' s' \<and>  sc_at' (ksCurSc s') s'"
              and r'=dc
               in corres_split')

     apply (rule corres_if_split; (solves simp)?)

      apply clarsimp
      apply (rule corres_guard_imp)
        apply (rule_tac n=n in refillNew_corres)
         apply (clarsimp simp: MIN_REFILLS_def)
        apply (clarsimp simp: valid_refills_number'_def MIN_REFILLS_def)
       apply fastforce
      apply simp

     apply (rule corres_if_split)
       apply (clarsimp simp: sc_relation_def)

      apply (rule corres_symb_exec_l[rotated 2, OF assert_opt_sp]; (solves wpsimp)?)
       apply (rule corres_split'[rotated 2, OF gts_sp isRunnable_sp])
        apply (corressimp corres: isRunnable_corres')
        apply (fastforce simp: sc_relation_def sc_at_pred_n_def obj_at_def
                       intro!: tcb_at_cross Some_to_the)

       apply (rule corres_if_split; (solves simp)?)

        apply (rule_tac Q="is_active_sc' sc_ptr" in corres_cross_add_guard)
         apply (fastforce simp: is_active_sc_rewrite[symmetric] sc_at_pred_n_def obj_at_def
                                is_sc_obj_def vs_all_heap_simps opt_map_def active_sc_def
                        intro!: is_active_sc'_cross)

        apply (rule corres_guard_imp)
          apply (rule_tac n=n in refillUpdate_corres)
           apply (clarsimp simp: MIN_REFILLS_def)
          apply (clarsimp simp: valid_refills_number'_def MIN_REFILLS_def)
         apply clarsimp
         apply (fastforce simp: is_active_sc_rewrite[symmetric] sc_at_pred_n_def obj_at_def
                                vs_all_heap_simps active_sc_def)
        apply (rule valid_objs'_valid_refills')
          apply fastforce
         apply (clarsimp simp: obj_at_simps ko_wp_at'_def)
         apply (rename_tac ko obj, case_tac ko; clarsimp)
        apply simp

      apply (rule corres_guard_imp)
        apply (rule_tac n=n in refillNew_corres)
         apply (clarsimp simp: MIN_REFILLS_def)
        apply (clarsimp simp: valid_refills_number'_def MIN_REFILLS_def)
       apply fastforce
      apply simp

     apply (rule corres_guard_imp)
       apply (rule_tac n=n in refillNew_corres)
        apply (clarsimp simp: MIN_REFILLS_def)
       apply (clarsimp simp: valid_refills_number'_def MIN_REFILLS_def)
      apply fastforce
     apply simp

    apply (find_goal \<open>match conclusion in "\<lbrace>P\<rbrace> f \<lbrace>Q\<rbrace>" for P f Q  \<Rightarrow> -\<close>)
    apply (rule hoare_if)
     apply (wps_conj_solves wp: refill_new_valid_sched_action refill_new_valid_release_q)
       apply (wpsimp wp: refill_new_active_sc_valid_refills)
       apply (clarsimp simp: current_time_bounded_def sc_at_pred_n_def obj_at_def)
      apply (wpsimp wp: refill_new_valid_ready_qs)
      apply (clarsimp simp: current_time_bounded_def active_sc_def MIN_REFILLS_def)
     apply (wpsimp wp: hoare_vcg_imp_lift' hoare_vcg_all_lift)

    apply (rule hoare_if)
     apply (rule hoare_seq_ext_skip, wpsimp)
     apply (rule hoare_seq_ext[OF _ gts_sp])
     apply (rule hoare_if)

      apply (wps_conj_solves wp: refill_update_valid_sched_action refill_update_invs)
         apply (wpsimp wp: refill_update_active_sc_valid_refills)
         apply (clarsimp simp: current_time_bounded_def sc_at_pred_n_def obj_at_def
                               active_sc_valid_refills_def vs_all_heap_simps active_sc_def)
        apply (wpsimp wp: refill_update_valid_ready_qs)
        apply (simp add: obj_at_kh_kheap_simps pred_map_eq_normalise)
       apply (wpsimp wp: refill_update_valid_release_q)
       apply (clarsimp simp: active_sc_valid_refills_def vs_all_heap_simps)
      apply (wpsimp wp: hoare_vcg_all_lift hoare_vcg_imp_lift')

     apply (wps_conj_solves wp: refill_new_valid_sched_action refill_new_valid_release_q)
       apply (wpsimp wp: refill_new_active_sc_valid_refills)
       apply (clarsimp simp: current_time_bounded_def sc_at_pred_n_def obj_at_def)
      apply (wpsimp wp: refill_new_valid_ready_qs)
      apply (clarsimp simp: current_time_bounded_def active_sc_def MIN_REFILLS_def)
     apply (wpsimp wp: hoare_vcg_imp_lift' hoare_vcg_all_lift)

     apply (wps_conj_solves wp: refill_new_valid_sched_action refill_new_valid_release_q)
       apply (wpsimp wp: refill_new_active_sc_valid_refills)
       apply (clarsimp simp: current_time_bounded_def sc_at_pred_n_def obj_at_def)
      apply (wpsimp wp: refill_new_valid_ready_qs)
      apply (clarsimp simp: current_time_bounded_def active_sc_def MIN_REFILLS_def)
     apply (wpsimp wp: hoare_vcg_imp_lift' hoare_vcg_all_lift)

   apply (find_goal \<open>match conclusion in "\<lbrace>P\<rbrace> f \<lbrace>Q\<rbrace>" for P f Q  \<Rightarrow> -\<close>)
   apply (rule hoare_if)
    apply wps_conj_solves
     apply (wpsimp wp: refillNew_invs')
    apply (clarsimp simp: ko_wp_at'_def valid_refills_number'_def)
   apply (rule hoare_if)
    apply wps_conj_solves
    apply (rule hoare_seq_ext[OF _ isRunnable_sp])
    apply (rule hoare_if)
     apply (wpsimp wp: refillUpdate_invs')
     apply (clarsimp simp: ko_wp_at'_def valid_refills_number'_def)
    apply (wpsimp wp: refillNew_invs')
    apply (clarsimp simp: ko_wp_at'_def valid_refills_number'_def)
   apply wps_conj_solves
   apply (wpsimp wp: refillNew_invs')
  apply (clarsimp simp: ko_wp_at'_def valid_refills_number'_def)

  apply (clarsimp simp: when_def; intro conjI impI; (solves \<open>clarsimp simp: sc_relation_def\<close>)?)
  apply (rule corres_symb_exec_l[rotated 2, OF assert_opt_sp]; (solves wpsimp)?)

  apply (rule_tac F="sc_tcb sc = Some tcb_ptr" in corres_req)
   apply fastforce

  apply (clarsimp simp: sc_relation_def)
  apply (rule corres_split'[rotated 2, OF gts_sp isRunnable_sp])
   apply (corressimp corres: isRunnable_corres')
   apply (fastforce simp: sc_relation_def sc_at_pred_n_def obj_at_def
                  intro!: tcb_at_cross Some_to_the)

  apply (rule corres_guard_imp)
    apply (rule corres_split[OF schedContextResume_corres])
      apply (rule corres_split[OF getCurThread_corres])
        apply (rule corres_if)
          apply fastforce
         apply (rule rescheduleRequired_corres)
        apply (rule corres_if)
       apply (clarsimp simp: thread_state_relation_def)
         apply (rule possibleSwitchTo_corres)
         apply clarsimp
        apply clarsimp
       apply wpsimp
      apply wpsimp
     apply ((wpsimp wp: hoare_vcg_imp_lift' sched_context_resume_valid_sched_action
            | strengthen valid_objs_valid_tcbs)+)[1]
    apply (rule_tac Q="\<lambda>_. invs'" in hoare_post_imp, fastforce)
    apply (wpsimp wp: schedContextResume_invs')
   apply (fastforce simp: sc_at_pred_n_def obj_at_def schact_is_rct_def
                   intro: valid_sched_action_weak_valid_sched_action)
  apply fastforce
  done

end

end
