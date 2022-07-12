(*
 * Copyright 2021, UNSW (ABN 57 195 873 179),
 * Copyright 2021, The University of Melbourne (ABN 84 002 705 224).
 *
 * SPDX-License-Identifier: GPL-2.0-only
 *)

theory TimeProtectionIntegration
imports TimeProtection
  "InfoFlow.Noninterference" schedule_oracle
begin

type_synonym if_other_state = "(user_context \<times> det_ext Structures_A.state) \<times> sys_mode"

locale integration_setup = 
  time_protection_hardware
    gentypes
    PSched +
  Noninterference_valid_initial_state _ _ _ _ initial_aag
  for gentypes :: "('fch \<times> 'fch_cachedness \<times> 'pch \<times> 'pch_cachedness \<times> 'l partition \<times> 'colour) itself"
  and initial_aag :: "'l subject_label PAS"
+ fixes time_per_tick :: time
  fixes fixme_WCET :: time
  fixes ta :: "if_other_state \<Rightarrow> vpaddr set"
begin

(* get the list of (domain, tickcount) from the initial state *)
(* this system assumes that domain_list_internal won't change *)
definition dom_list_internal where
  "dom_list_internal \<equiv> domain_list_internal $ exst $ snd $ fst s0"

(* map dom_list_internal into a list of (domain, totaltime) by multiplying
   by time_per_tick *)
definition schedule_list where
  "schedule_list \<equiv> map (\<lambda>(d, ticks). (data_to_nat ticks * time_per_tick, d)) dom_list_internal"

interpretation sched_o:schedule_oracle _ schedule_list fixme_WCET
  apply unfold_locales
   (* we need to know that the domain list has some minimum time *)
   subgoal sorry
  (* we need to know that the domain list is never empty *)
  subgoal sorry
  done

definition nlds where
  "nlds \<equiv> sched_o.slice_end"

lemma nlds_in_future:
  "t \<le> nlds t"
  apply (clarsimp simp:nlds_def)
  apply (simp add: le_simps(1) sched_o.slice_end_gt)
  done

lemma nlds_step:
  "\<lbrakk>t \<le> t'; t' \<le> nlds t\<rbrakk> \<Longrightarrow> nlds t' = nlds t"
  sledgehammer
                    
interpretation tphuwr:time_protection_hardware_uwr gentypes PSched 
  _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ part uwr nlds ta
  apply unfold_locales
   apply (simp add: schedIncludesCurrentDom)
  using uwr_equiv_rel apply blast
  done

abbreviation ma_uwr where "ma_uwr \<equiv> tphuwr.uwr"

(*
(* the definition used in infoflow *)
definition if_A where
  "if_A \<equiv> big_step_ADT_A_if utf"

definition if_s0 where
  "if_s0 \<equiv> s0"

definition if_current_domain :: "if_other_state \<Rightarrow> 'l partition" where
  "if_current_domain \<equiv> part"

definition if_uwr :: "'l partition \<Rightarrow> (if_other_state \<times> if_other_state) set" where
  "if_uwr d \<equiv> uwr d"

(* the definition used in infoflow *)
definition if_policy :: "('l partition \<times> 'l partition) set" where
  "if_policy \<equiv> policyFlows (pasPolicy initial_aag)"
 *)

end

locale integration =
  ii?:integration_setup _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ gentypes +
  ts?:trace_selector
    "TYPE((if_other_state \<times> ('fch, 'pch) TimeProtection.state) \<times> 'l partition \<times> trace \<times> vpaddr set)"
    "ii.part \<circ> fst" ma_uwr PSched "[]" "step_is_uwr_determined \<circ> fst" "step_is_publicly_determined \<circ> fst" select_trace 
  for gentypes :: "('fch \<times> 'fch_cachedness \<times> 'pch \<times> 'pch_cachedness \<times> 'l partition \<times> 'colour) itself"
  and select_trace and step_is_uwr_determined and step_is_publicly_determined
begin

(*
pch_read_impact :: "paddr \<Rightarrow> 'pch \<Rightarrow> 'pch"
    and pch_write_impact :: "paddr \<Rightarrow> 'pch \<Rightarrow> 'pch"
    and do_pch_flush :: "'pch \<Rightarrow> paddr set \<Rightarrow> 'pch"
    and pch_flush_cycles :: "'pch \<Rightarrow> paddr set \<Rightarrow> nat"
    and pch_flush_WCET :: "paddr set \<Rightarrow> nat"
    and collides_in_pch :: "paddr \<Rightarrow> paddr \<Rightarrow> bool"  (infix \<open>coll\<close> 50)
    and read_cycles :: "'fch_cachedness \<Rightarrow> 'pch_cachedness \<Rightarrow> nat"
    and write_cycles :: "'fch_cachedness \<Rightarrow> 'pch_cachedness \<Rightarrow> nat"
    and addr_domain :: "paddr \<Rightarrow> 'domain"
    and addr_colour :: "paddr \<Rightarrow> 'colour"
    and colour_userdomain :: "'colour \<Rightarrow> 'domain"
 *)

interpretation ma?:time_protection_system PSched fch_lookup fch_read_impact fch_write_impact
  empty_fch fch_flush_cycles fch_flush_WCET pch_lookup pch_read_impact pch_write_impact do_pch_flush
  pch_flush_cycles pch_flush_WCET collides_in_pch read_cycles write_cycles addr_domain addr_colour colour_userdomain
  part uwr nlds ta select_trace
  "big_step_ADT_A_if utf" s0 "policyFlows (pasPolicy initial_aag)" _
  
  apply unfold_locales
               using schedIncludesCurrentDom apply presburger
              apply (simp add: uwr_equiv_rel)
             subgoal sorry
            apply (rule nlds_in_future)
           subgoal sorry
          subgoal sorry
         subgoal sorry
        subgoal sorry
       subgoal sorry
      subgoal sorry
     subgoal sorry
    subgoal sorry
   subgoal sorry
  subgoal sorry
  done
end

end