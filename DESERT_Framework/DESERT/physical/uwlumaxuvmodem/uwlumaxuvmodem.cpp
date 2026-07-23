//
// Copyright (c) 2019 Regents of the SIGNET lab, University of Padova.
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions
// are met:
// 1. Redistributions of source code must retain the above copyright
//    notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the distribution.
// 3. Neither the name of the University of Padova (SIGNET lab) nor the
//    names of its contributors may be used to endorse or promote products
//    derived from this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
// TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
// CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
// EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
// PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
// OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
// WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
// OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
// ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#include "phymac-clmsg.h"
#include "uwmodem.h"

#include <fcntl.h>
#include <memory>
#include <mutex>
#include <sys/socket.h>
#include <uwlumaxuvmodem.h>
#include <uwsocket.h>

#include <algorithm>
#include <functional>
#include <string>

const std::chrono::milliseconds UwLumaXUVModem::MODEM_TIMEOUT =
		std::chrono::milliseconds(3000);

UwLumaXUVModem::UwLumaXUVModem()
	: UwModem()
	, status_m()
	, status(ModemState::AVAILABLE)
	, tx_queue_m()
	, tx_queue_cv()
	, receiving(false)
	, transmitting(false)
	, rx_payload("")
	, sig_thread()
	, rx_thread()
	, tx_thread()
	, config_conn(new UwSocket()) // TODO
	, modem_address("")
	, send_conn(new UwSocket())
	, recv_conn(new UwSocket())
	, data_address("")
	, signal_buffer()
	, signal_tag("DRIVER")
	, premodulation(0)
{
	send_conn->setUDP();
	send_conn->setMulticast();

	recv_conn->setUDP();
	recv_conn->setMulticast();
	// this set recv_conn in reception mode (server receives data)
	recv_conn->setServer();

	data_buffer.clear();
}

UwLumaXUVModem::~UwLumaXUVModem()
{
	stop();
}

void
UwLumaXUVModem::recv(Packet *p)
{
	hdr_cmn *ch = HDR_CMN(p);
	hdr_MPhy *ph = HDR_MPHY(p);

	if (ch->direction() == hdr_cmn::UP) {
		if (isOn) {
			startRx(p);
			endRx(p);
		} else {
			Packet::free(p);
		}
	} else { // hdr_cmn::DOWN
		if (!isOn) {
			return;
		}
		ph->Pr = 0;
		ph->Pn = 0;
		ph->Pi = 0;
		ph->txtime = NOW;
		ph->rxtime = ph->txtime;

		ph->worth_tracing = false;

		// TODO
		ph->srcSpectralMask = getTxSpectralMask(p);
		ph->srcAntenna = getTxAntenna(p);
		ph->srcPosition = getPosition();
		ph->dstSpectralMask = 0;
		ph->dstPosition = 0;
		ph->dstAntenna = 0;
		ph->modulationType = getModulationType(p);
		ph->duration = getTxDuration(p);

		std::unique_lock<std::mutex> tx_lock(tx_queue_m);
		tx_queue.push(p);
		tx_lock.unlock();
		printOnLog(
				LogLevel::DEBUG, "LUMAXUVMODEM", "recv::PUSHING_IN_TX_QUEUE");
		tx_queue_cv.notify_one();
	}
	return;
}

int
UwLumaXUVModem::command(int argc, const char *const *argv)
{
	if (argc == 3) {
		if (!strcmp(argv[1], "setModemAddress")) { // TODO
			modem_address = argv[2];
			return TCL_OK;
		}
		// local network interface address that the modem will send multicast
		// messages to
		if (!strcmp(argv[1], "setLocalAddress")) {
			data_address = argv[2];
			return TCL_OK;
		}
		if (!strcmp(argv[1], "setMulticastAddress")) {
			if (send_conn->setMulticastAddress(argv[2]) &&
					recv_conn->setMulticastAddress(argv[2])) {
				return TCL_OK;
			}
		}
	}
	return UwModem::command(argc, argv);
}

int
UwLumaXUVModem::getModulationType(Packet *P)
{
	return 0;
}

double
UwLumaXUVModem::getTxDuration(Packet *p)
{
	hdr_uwal *uwalh = HDR_UWAL(p);
	double tx_duration = -1;

	// With Flexframe modulation, the TX duration is obtained
	// dividing the number of samples written by the sampling frequency
	// (192 kHz by default).
	// It can be written as a linear function of the packet size:
	// tx_duration = a + b * pkt_size
	// The two constants a = 0.560833333 [s] and b = 0.013333333 [s]
	// are obtained by interpolating the TX duration values obtained
	// with the smallest and biggest packet size possible.
	tx_duration = 0.560833333 + 0.013333333 * (uwalh->binPktLength());

	if (premodulation)
		tx_duration += 0.1;

	return tx_duration;
}

int
UwLumaXUVModem::recvSyncClMsg(ClMessage *m)
{
	if (m->type() == CLMSG_MAC2PHY_GETTXDURATION) {
		Packet *p = ((ClMsgMac2PhyGetTxDuration *) m)->pkt;
		hdr_cmn *ch = HDR_CMN(p);

		if (ch->direction() == hdr_cmn::DOWN) {
			double duration = getTxDuration(p);

			if (duration > 0)
				printOnLog(LogLevel::INFO,
						"LUMAXUVMODEM",
						"recvSyncClMsg::GET_TXDURATION " +
								std::to_string(duration));

			((ClMsgMac2PhyGetTxDuration *) m)->setDuration(duration);

			return 0;
		}

		// Don't set TX duration on RX.
		((ClMsgMac2PhyGetTxDuration *) m)->setDuration(-1);

		return 1;
	}

	return MPhy::recvSyncClMsg(m);
}

void
UwLumaXUVModem::start()
{
	printOnLog(LogLevel::DEBUG, "LUMAXUVMODEM", "STARTING_DRIVER");
	// TODO implement modem configuration logic
	// if (!config_conn->openConnection(modem_address)) {
	// 	std::string err_msg =
	// 			"CONFIG_CHANNEL_FAILED_TO_OPEN_AT_PORT:" + modem_address;
	// 	printOnLog(LogLevel::ERROR, "LUMAXUVMODEM", err_msg);
	// 	return;
	// }

	if (!send_conn->openConnection(data_address)) {
		std::string err_msg =
				"SENDING_SOCKET_FAILED_TO_OPEN_WITH_ADDRESS:" + data_address;
		printOnLog(LogLevel::ERROR, "LUMAXUVMODEM", err_msg);
		err_msg = "address should have no port";
		printOnLog(LogLevel::DEBUG, "LUMAXUVMODEM", err_msg);
		return;
	} else {
		printOnLog(LogLevel::INFO,
				"LUMAXUVMODEM",
				"SENDING_CONNECTION_ESTABLISHED:" + data_address);
	}

	if (!recv_conn->openConnection(data_address)) {
		std::string err_msg =
				"RECEIVING_SOCKET_FAILED_TO_OPEN_WITH_ADDRESS:" + data_address;
		printOnLog(LogLevel::ERROR, "LUMAXUVMODEM", err_msg);
		err_msg = "address should have no port";
		printOnLog(LogLevel::DEBUG, "LUMAXUVMODEM", err_msg);
		return;
	} else {
		printOnLog(LogLevel::INFO,
				"LUMAXUVMODEM",
				"RECEIVING_CONNECTION_ESTABLISHED:" + data_address);
	}
	// set flags to true so loops can start
	receiving.store(true);
	transmitting.store(true);

	// Dispatch threads
	rx_thread = std::thread(&UwLumaXUVModem::receivingData, this);
	tx_thread = std::thread(&UwLumaXUVModem::transmittingData, this);

	checkTimer = new CheckTimer(this);
	checkTimer->resched(period);
}

void
UwLumaXUVModem::stop()
{
	receiving.store(false);
	transmitting.store(false);

	status_cv.notify_all();
	tx_queue_cv.notify_all();

	if (tx_thread.joinable())
		tx_thread.join();

	if (config_conn->isConnected() && !config_conn->closeConnection())
		printOnLog(LogLevel::ERROR,
				"LUMAXUVMODEM",
				"CONFIG_CONNECTION_UNABLE_TO_CLOSE");
	if (send_conn->isConnected() && !send_conn->closeConnection())
		printOnLog(LogLevel::ERROR,
				"LUMAXUVMODEM",
				"SEND_CONNECTION_UNABLE_TO_CLOSE");

	if (recv_conn->isConnected() && !recv_conn->closeConnection())
		printOnLog(LogLevel::ERROR,
				"LUMAXUVMODEM",
				"RECEIVE_CONNECTION_UNABLE_TO_CLOSE");

	if (sig_thread.joinable())
		sig_thread.join();
	if (rx_thread.joinable())
		rx_thread.join();

	if (checkTimer) {
		checkTimer->force_cancel();
	}
}

void
UwLumaXUVModem::receivingData()
{
	data_buffer.resize(DATA_BUFFER_LEN, '\0');
	std::fill(data_buffer.begin(), data_buffer.end(), '\0');

	printOnLog(UwModem::LogLevel::DEBUG, "LUMAXUV", "Reached reading loop");
	while (receiving.load()) {
		// std::unique_lock<std::mutex> state_lock(status_m);
		// if (status_cv.wait_for(state_lock, MODEM_TIMEOUT, [&] {
		// 		return status == ModemState::RECEIVING;
		// 	})) {

		auto beg_it = data_buffer.begin();
		int r_bytes = recv_conn->readFromDevice(&(*beg_it), MAX_READ_BYTES);

		if (r_bytes > 0) {
			std::unique_lock<std::mutex> state_lock(status_m);
			status = ModemState::RECEIVING;
			state_lock.unlock();

			printOnLog(UwModem::LogLevel::DEBUG,
					"LUMAXUV",
					"read " + std::to_string(r_bytes) + " bytes");

			rx_payload = std::string(beg_it, beg_it + r_bytes);
			printOnLog(LogLevel::DEBUG,
					"LUMAXUVMODEM",
					"receivingData::LEN::" + std::to_string(rx_payload.size()) +
							"::DATA::" + rx_payload);

			Packet *p = Packet::alloc();
			createRxPacket(p);
			std::function<void(UwModem &, Packet * p)> callback =
					&UwModem::recv;
			ModemEvent e = {callback, p};
			event_q.push(e);

			state_lock.lock();
			status = ModemState::AVAILABLE;
			status_cv.notify_all();

		} else {
			printOnLog(UwModem::LogLevel::DEBUG,
					"LUMAXUV",
					"failed if to read from device");
		}
	}
}

void
UwLumaXUVModem::createRxPacket(Packet *p)
{
	hdr_uwal *uwalh = HDR_UWAL(p);
	uwalh->binPktLength() = rx_payload.size();
	std::memset(uwalh->binPkt(), 0, uwalh->binPktLength());
	std::copy(rx_payload.begin(), rx_payload.end(), uwalh->binPkt());
	HDR_CMN(p)->direction() = hdr_cmn::UP;
}

void
UwLumaXUVModem::transmittingData()
{
	printOnLog(
			UwModem::LogLevel::DEBUG, "LUMAXUVMODEM", "STARTING_TRANSMISSION");

	while (transmitting.load()) {
		std::unique_lock<std::mutex> tx_lock(tx_queue_m);
		tx_queue_cv.wait(
				tx_lock, [&] { return !tx_queue.empty() || !transmitting; });

		if (!transmitting.load())
			break;

		Packet *pck = tx_queue.front();
		tx_queue.pop();
		tx_lock.unlock();
		if (pck) {
			std::cout << "pacchetto inviato" << std::endl;
			startTx(pck);
		}

		printOnLog(LogLevel::DEBUG,
				"LUMAXUVMODEM",
				"transmittingData::BLOCKING_ON_NEXT_PACKET");
	}
}

void
UwLumaXUVModem::startTx(Packet *p)
{
	hdr_uwal *uwalh = HDR_UWAL(p);
	std::string payload;
	payload.assign(uwalh->binPkt(), uwalh->binPktLength());

	std::unique_lock<std::mutex> state_lock(status_m);
	if (status_cv.wait_for(state_lock, MODEM_TIMEOUT, [&] {
			return status == ModemState::AVAILABLE;
		})) {

		status = ModemState::TRANSMITTING;
		state_lock.unlock();

		if ((send_conn->writeToDevice(payload)) < 0) {
			printOnLog(LogLevel::ERROR,
					"LUMAXUVMODEM",
					"startTx::FAIL_TO_WRITE_DATA_TO_DEVICE");

			state_lock.lock();
			status = ModemState::AVAILABLE;
			status_cv.notify_all();
			return;
		}

		std::function<void(UwModem &, Packet * p)> callback =
				&UwModem::realTxEnded;
		ModemEvent e = {callback, p};
		event_q.push(e);

		printOnLog(
				LogLevel::INFO, "LUMAXUVMODEM", "startTx::PACKET_TRANSMITTED");

		state_lock.lock();
		status = ModemState::AVAILABLE;
		status_cv.notify_all();
	}
}

void
UwLumaXUVModem::startRx(Packet *p)
{
	printOnLog(LogLevel::INFO, "LUMAXUVMODEM", "startRx::CALL_PHY2MACSTARTRX");
	Phy2MacStartRx(p);
}

void
UwLumaXUVModem::endRx(Packet *p)
{
	printOnLog(LogLevel::INFO, "LUMAXUVMODEM", "endRx::CALL_SENDUP");
	sendUp(p, 0.01);
}
