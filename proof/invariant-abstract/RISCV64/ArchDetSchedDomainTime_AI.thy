(*
 * Copyright 2020, Data61, CSIRO (ABN 41 687 119 230)
 *
 * SPDX-License-Identifier: GPL-2.0-only
 *)

theory ArchDetSchedDomainTime_AI
imports DetSchedDomainTime_AI
begin

context Arch begin global_naming RISCV64

named_theorems DetSchedDomainTime_AI_assms

lemma set_per_domain_default_vm_root_domain_list:
  "\<And>P. do_extended_op (do
     curdom <- gets cur_domain;
     ki_vspace <- gets domain_kimage_vspace;
     ki_asid <- gets domain_kimage_asid;
     do_machine_op (setVSpaceRoot (addrFromPPtr (ki_vspace curdom)) (ucast (ki_asid curdom)))
   od)
   \<lbrace>\<lambda>s. P (domain_list s)\<rbrace>"
  (* TODO: Made necessary by experimental-tpspec. -robs *)
  sorry

lemma set_per_domain_default_vm_root_domain_time:
  "\<And>P. do_extended_op (do
     curdom <- gets cur_domain;
     ki_vspace <- gets domain_kimage_vspace;
     ki_asid <- gets domain_kimage_asid;
     do_machine_op (setVSpaceRoot (addrFromPPtr (ki_vspace curdom)) (ucast (ki_asid curdom)))
   od)
   \<lbrace>\<lambda>s. P (domain_time s)\<rbrace>"
  (* TODO: Made necessary by experimental-tpspec. -robs *)
  sorry

crunch domain_list_inv[wp]: set_vm_root "\<lambda>s. P (domain_list s)"
  (wp: set_per_domain_default_vm_root_domain_list get_cap_wp find_vspace_for_asid_wp)

crunch domain_time_inv[wp]: set_vm_root "\<lambda>s. P (domain_time s)"
  (wp: set_per_domain_default_vm_root_domain_time find_vspace_for_asid_wp)

crunch domain_list_inv [wp, DetSchedDomainTime_AI_assms]: arch_finalise_cap "\<lambda>s. P (domain_list s)"
  (wp: hoare_drop_imps mapM_wp subset_refl find_vspace_for_asid_wp pt_lookup_from_level_tainv
   simp: crunch_simps ta_agnostic_def)

crunch domain_list_inv [wp, DetSchedDomainTime_AI_assms]:
  arch_activate_idle_thread, arch_switch_to_thread, arch_switch_to_idle_thread,
  handle_arch_fault_reply,
  arch_invoke_irq_control, arch_get_sanitise_register_info,
  prepare_thread_delete, handle_hypervisor_fault, make_arch_fault_msg,
  arch_post_modify_registers, arch_post_cap_deletion, handle_vm_fault,
  arch_invoke_irq_handler,
  arch_mask_interrupts, arch_switch_domain_kernel, arch_domainswitch_flush
  "\<lambda>s. P (domain_list s)"
  (wp: crunch_wps simp: crunch_simps)

crunch domain_time_inv [wp, DetSchedDomainTime_AI_assms]: arch_finalise_cap "\<lambda>s. P (domain_time s)"
  (wp: hoare_drop_imps mapM_wp subset_refl pt_lookup_from_level_tainv find_vspace_for_asid_wp
   simp: crunch_simps ta_agnostic_def)

crunch domain_time_inv [wp, DetSchedDomainTime_AI_assms]:
  arch_activate_idle_thread, arch_switch_to_thread, arch_switch_to_idle_thread,
  handle_arch_fault_reply, init_arch_objects,
  arch_invoke_irq_control, arch_get_sanitise_register_info,
  prepare_thread_delete, handle_hypervisor_fault, handle_vm_fault,
  arch_post_modify_registers, arch_post_cap_deletion, make_arch_fault_msg,
  arch_invoke_irq_handler,
  arch_mask_interrupts, arch_switch_domain_kernel, arch_domainswitch_flush
  "\<lambda>s. P (domain_time s)"
  (wp: crunch_wps simp: crunch_simps)

crunches do_machine_op
  for exst[wp]: "\<lambda>s. P (exst s)"

declare init_arch_objects_exst[DetSchedDomainTime_AI_assms]

end

global_interpretation DetSchedDomainTime_AI?: DetSchedDomainTime_AI
  proof goal_cases
  interpret Arch .
  case 1 show ?case by (unfold_locales; (fact DetSchedDomainTime_AI_assms)?)
  qed

context Arch begin global_naming RISCV64

crunch domain_time_inv [wp, DetSchedDomainTime_AI_assms]: arch_perform_invocation "\<lambda>s. P (domain_time s)"
  (wp: crunch_wps check_cap_inv)

crunch domain_list_inv [wp, DetSchedDomainTime_AI_assms]: arch_perform_invocation "\<lambda>s. P (domain_list s)"
  (wp: crunch_wps check_cap_inv)

lemma timer_tick_valid_domain_time:
  "\<lbrace> \<lambda>s :: det_ext state. 0 < domain_time s \<rbrace>
   timer_tick
   \<lbrace>\<lambda>x s. domain_time s = 0 \<longrightarrow> scheduler_action s = choose_new_thread\<rbrace>" (is "\<lbrace> ?dtnot0 \<rbrace> _ \<lbrace> _ \<rbrace>")
  unfolding timer_tick_def
  supply if_split[split del]
  supply ethread_get_wp[wp del]
  supply if_apply_def2[simp]
  apply (wpsimp
           wp: reschedule_required_valid_domain_time hoare_vcg_const_imp_lift gts_wp
               touch_object_wp'
               (* unless we hit dec_domain_time we know ?dtnot0 holds on the state, so clean up the
                  postcondition once we hit thread_set_time_slice *)
               hoare_post_imp[where Q="\<lambda>_. ?dtnot0" and R="\<lambda>_ s. domain_time s = 0 \<longrightarrow> X s"
                                and a="thread_set_time_slice t ts" for X t ts]
               hoare_drop_imp[where f="ethread_get t f" for t f])
  apply fastforce
  done

lemma handle_interrupt_valid_domain_time [DetSchedDomainTime_AI_assms]:
  "\<lbrace>\<lambda>s :: det_ext state. 0 < domain_time s \<rbrace>
   handle_interrupt i
   \<lbrace>\<lambda>rv s.  domain_time s = 0 \<longrightarrow> scheduler_action s = choose_new_thread \<rbrace>" (is "\<lbrace> ?dtnot0 \<rbrace> _ \<lbrace> _ \<rbrace>")
  unfolding handle_interrupt_def
  apply (case_tac "maxIRQ < i", solves \<open>wpsimp wp: hoare_false_imp\<close>)
  apply clarsimp
  apply (wpsimp simp: arch_mask_irq_signal_def)
         apply (rule hoare_post_imp[where Q="\<lambda>_. ?dtnot0" and a="send_signal p c" for p c], fastforce)
         apply wpsimp
        apply (wpsimp wp: get_cap_wp)
       apply (wpsimp wp: touch_object_wp')
       sorry (* FIXME: broken by touched-addrs -robs
       apply (rule hoare_post_imp[where Q="\<lambda>_. ?dtnot0" and a="get_cap p" for p], fastforce)
      apply (wpsimp wp: timer_tick_valid_domain_time simp: handle_reserved_irq_def)+
     apply (rule hoare_post_imp[where Q="\<lambda>_. ?dtnot0" and a="get_irq_state i" for i], fastforce)
   apply wpsimp+
  done
*)

crunches handle_reserved_irq, arch_mask_irq_signal
  for domain_time_inv [wp, DetSchedDomainTime_AI_assms]: "\<lambda>s. P (domain_time s)"
  and domain_list_inv [wp, DetSchedDomainTime_AI_assms]: "\<lambda>s. P (domain_list s)"
  (wp: crunch_wps mapM_wp subset_refl simp: crunch_simps)

end

global_interpretation DetSchedDomainTime_AI_2?: DetSchedDomainTime_AI_2
  proof goal_cases
  interpret Arch .
  case 1 show ?case by (unfold_locales; (fact DetSchedDomainTime_AI_assms)?)
  qed

end
