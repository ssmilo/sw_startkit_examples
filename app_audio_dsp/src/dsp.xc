/******************************************************************************\
 * The copyrights, all other intellectual and industrial
 * property rights are retained by XMOS and/or its licensors.
 * Terms and conditions covering the use of this code can
 * be found in the Xmos End User License Agreement.
 *
 * Copyright XMOS Ltd 2014
 *
 * In the case where this code is a modification of existing code
 * under a separate license, the separate license terms are shown
 * below. The modifications to the code are still covered by the
 * copyright notice above.
 *
\******************************************************************************/

#include "app_conf.h"
#include "app_global.h"
#include "dsp.h"
#include "coeffs.h"
#include "biquadCascade.h"
#include "drc.h"
#include "xscope.h"

static inline void handle_control(server control_if i_control, dsp_state_t &state, int &gain,
    biquadState bs[])
{
  select {
    case i_control.set_effect(dsp_state_t next_state) :
      state = next_state;
      break;

    case i_control.set_gain(int new_gain) :
      gain = new_gain;
      break;

    case i_control.set_dbs(int chan_index, int bank, int dbs) :
      for (int c = 0; c < NUM_APP_CHANS; c++) {
        for (int i = 0; i < BANKS; i++) {
          if ((chan_index == NUM_APP_CHANS || chan_index == c) &&
              (bank == BANKS || bank == i)) {
            bs[c].desiredDb[i] = dbs;
          }
        }
      }
      break;

    case i_control.get_dbs(int chan_index, int index) -> int dbs:
      if (index < BANKS) {
        dbs = bs[chan_index].b[index].db;
      } else {
        dbs = 0;
      }
      break;

    default:
      break;
  }
}

void dsp(streaming chanend c_audio, server control_if i_control)
{
  biquadState bs[NUM_APP_CHANS];

  int gain = 0; // Initial gain is set in the control core

  int inp_samps[NUM_APP_CHANS];
  int equal_samps[NUM_APP_CHANS];
  int out_samps[NUM_APP_CHANS];

  dsp_state_t cur_proc_state = 0;

  initDrc();

  for (int chan_cnt = 0; chan_cnt < NUM_APP_CHANS; chan_cnt++)
  {
    // Initialise all state
    initBiquads(bs[chan_cnt], 20);
    inp_samps[chan_cnt] = 0;
    equal_samps[chan_cnt] = 0;
    out_samps[chan_cnt] = 0;
  }

  // Loop forever
  while(1)
  {
    // Send/Receive samples over Audio coar channel
#pragma loop unroll
    for (int chan_cnt = 0; chan_cnt < NUM_APP_CHANS; chan_cnt++)
    {
c_audio :> inp_samps[chan_cnt];
         inp_samps[chan_cnt] >>= 8;
         c_audio <: out_samps[chan_cnt] << 8;
    }
    xscope_int(0,inp_samps[0]);
    xscope_int(1,out_samps[0]);
    xscope_int(2, gain);

    for (int chan_cnt = 0; chan_cnt < NUM_APP_CHANS; chan_cnt++)
    {
      int b_sample = biquadCascade(bs[chan_cnt], inp_samps[chan_cnt]);

      int d_sample;
      if (BIQUAD_ENABLED(cur_proc_state)) {
        d_sample = drc(b_sample);
      } else {
        d_sample = drc(inp_samps[chan_cnt]);
      }

      if (DRC_ENABLED(cur_proc_state)) {
        equal_samps[chan_cnt] = d_sample;
      } else {
        equal_samps[chan_cnt] = b_sample;
      }
    }

    handle_control(i_control, cur_proc_state, gain, bs);

    if (cur_proc_state) {
      for (int chan_cnt = 0; chan_cnt < NUM_APP_CHANS; chan_cnt++)
        out_samps[chan_cnt] = equal_samps[chan_cnt];
    } else {
      for (int chan_cnt = 0; chan_cnt < NUM_APP_CHANS; chan_cnt++)
        out_samps[chan_cnt] = inp_samps[chan_cnt];
    }

    for (int chan_cnt = 0; chan_cnt < NUM_APP_CHANS; chan_cnt++)
      out_samps[chan_cnt] = do_gain(out_samps[chan_cnt], gain);
  } // while(1)
}

