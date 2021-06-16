void do_simpleanimcode(int client, int entity, AnimInfo anim, StringMap seq_cache, StringMap pose_cache, LegType legtype, StringMap animnames)
{
	float vel[3];
	GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", vel);

	int buttons = GetEntProp(client, Prop_Data, "m_nButtons");
	bool m_bDucked = view_as<bool>(GetEntProp(client, Prop_Send, "m_bDucked"));
	int GroundEntity = GetEntPropEnt(client, Prop_Send, "m_hGroundEntity");
	bool m_bSequenceFinished = view_as<bool>(GetEntProp(entity, Prop_Data, "m_bSequenceFinished"));

	if(legtype != leg_ignore) {
		float eye[3];
		GetClientEyeAngles(client, eye);

		float fwd[3];
		float right[3];
		GetAngleVectors(eye, fwd, right, NULL_VECTOR);

		switch(legtype) {
			case leg_8yaw: {
				float x = GetVectorDotProduct(fwd, vel);
				float z = GetVectorDotProduct(right, vel);

				float yaw = (ArcTangent2(-z, x) * 180.0 / M_PI);

				int move_yaw = LookupPoseParameterCached(pose_cache, entity, "move_yaw");
				view_as<BaseAnimating>(entity).SetPoseParameter(move_yaw, yaw);
			}
			case leg_9way: {
				float x = GetVectorDotProduct(vel, fwd);
				float y = GetVectorDotProduct(vel, right);

				int move_x = LookupPoseParameterCached(pose_cache, entity, "move_x");
				view_as<BaseAnimating>(entity).SetPoseParameter(move_x, x);

				int move_y = LookupPoseParameterCached(pose_cache, entity, "move_y");
				view_as<BaseAnimating>(entity).SetPoseParameter(move_y, y);
			}
		}
	}

	bool moving = (GetVectorLength2D(vel) > 3.0);

	if(GroundEntity != -1 && anim.m_hOldGroundEntity == GroundEntity) {
		if(!anim.m_bDidJustLand) {
			if(anim.m_bCanAnimate) {
				if((buttons & IN_ANYMOVEMENTKEY) && moving) {
					int sequence = LookupSequenceCached(seq_cache, entity, "run", animnames);
					if(buttons & IN_SPEED) {
						sequence = LookupSequenceCached(seq_cache, entity, "walk", animnames);
					}
					if(m_bDucked) {
						sequence = LookupSequenceCached(seq_cache, entity, "crouch_move", animnames);
					}
					view_as<BaseAnimating>(entity).ResetSequence(sequence);
				} else {
					int sequence = LookupSequenceCached(seq_cache, entity, "idle", animnames);
					if(m_bDucked) {
						sequence = LookupSequenceCached(seq_cache, entity, "crouch_idle", animnames);
					}
					view_as<BaseAnimating>(entity).ResetSequence(sequence);
				}
			}
		} else {
			if(anim.m_bWillHardLand) {
				anim.m_bCanAnimate = true;
				anim.m_bWillHardLand = false;
				anim.m_bDidJustLand = false;
			} else {
				anim.m_bDidJustLand = false;
			}
		}
	}

	if(GroundEntity == -1 && anim.m_hOldGroundEntity != -1) {
		bool m_bJumping = view_as<bool>(GetEntProp(client, Prop_Send, "m_bJumping"));
		if(m_bJumping) {
			anim.m_bDidJustJump = true;
		}
	}

	if(GroundEntity == -1) {
		if(anim.m_bDidJustJump) {
			int sequence = LookupSequenceCached(seq_cache, entity, "jump", animnames);
			view_as<BaseAnimating>(entity).ResetSequence(sequence);
			if(m_bSequenceFinished) {
				anim.m_bDidJustJump = false;
			}
		} else {
			int sequence = LookupSequenceCached(seq_cache, entity, "in_air", animnames);
			view_as<BaseAnimating>(entity).ResetSequence(sequence);
		}
	}

	float m_flFallVelocity = GetEntPropFloat(client, Prop_Send, "m_flFallVelocity");
	if(m_flFallVelocity >= 500.0) {
		anim.m_bWillHardLand = true;
	}

	if(GroundEntity != -1 && anim.m_hOldGroundEntity == -1) {
		anim.m_bDidJustLand = true;
	}

	anim.m_hOldGroundEntity = GroundEntity;
	anim.m_nOldButtons = buttons;
	anim.m_bWasDucked = m_bDucked;
}